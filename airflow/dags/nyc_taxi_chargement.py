"""Pipeline mensuel NYC Yellow Taxi : chargement RAW, transformations, contrôles.

Une exécution = un mois, déduit de la date logique (jamais de la date du jour).
Ordre : chargement -> contrôle RAW -> tables mensuelles -> STAGING -> INTERMEDIATE
        -> contrôles qualité -> MARTS. Un contrôle en échec bloque la suite.
"""
import tempfile
from datetime import timedelta
from pathlib import Path

import requests
from airflow.sdk import TaskGroup, dag, task
from airflow.providers.common.sql.operators.sql import (
    SQLCheckOperator,
    SQLExecuteQueryOperator,
)
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from pendulum import datetime

CONN_ID = "snowflake_nyc_taxi"
BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data"
STAGE = "@NYC_TAXI.RAW.TLC_STAGE"
MOIS = "{{ logical_date.strftime('%Y-%m') }}"


def sql_task(chemin: str) -> SQLExecuteQueryOperator:
    """Une tâche = un fichier SQL. Le nom de la tâche est celui du fichier."""
    return SQLExecuteQueryOperator(
        task_id=Path(chemin).stem,
        conn_id=CONN_ID,
        sql=chemin,
        split_statements=True,      # certains fichiers enchaînent DELETE puis INSERT
    )


def controle(chemin: str) -> SQLCheckOperator:
    """Échoue si une valeur de la ligne renvoyée est fausse, nulle ou égale à 0."""
    return SQLCheckOperator(
        task_id=Path(chemin).stem,
        conn_id=CONN_ID,
        sql=chemin,
        retries=0,                  # un contrôle en échec doit échouer tout de suite
    )


@dag(
    schedule="@monthly",
    start_date=datetime(2025, 1, 1),
    end_date=datetime(2025, 3, 31),
    catchup=True,
    max_active_runs=1,
    template_searchpath="/usr/local/airflow/include/sql",   # où trouver les fichiers SQL
    params={
        "max_trip_distance_miles": 100,
        "max_trip_duration_min": 180,
        "start_month": "2025-01-01",
        "end_month": "2025-04-01",
        "max_rejection_rate": 0.15,     # notre seuil : au-delà, le mois est suspect
    },
    default_args={"retries": 2, "retry_delay": timedelta(minutes=2)},
    tags=["nyc_taxi"],
)
def nyc_taxi_chargement():

    # ---------- Chargement (jour 3) ----------
    @task
    def verifier_fichier(mois: str) -> str:
        url = f"{BASE_URL}/yellow_tripdata_{mois}.parquet"
        r = requests.head(url, timeout=30)
        if r.status_code != 200:
            raise ValueError(f"Fichier indisponible (HTTP {r.status_code}) : {url}")
        return url

    @task
    def telecharger_et_deposer(url: str) -> None:
        path = Path(tempfile.gettempdir()) / url.rsplit("/", 1)[-1]
        with requests.get(url, stream=True, timeout=60) as r:
            r.raise_for_status()
            with open(path, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024 * 1024):
                    f.write(chunk)
        hook = SnowflakeHook(snowflake_conn_id=CONN_ID)
        with hook.get_conn() as conn:
            conn.cursor().execute(f"PUT 'file://{path}' {STAGE} AUTO_COMPRESS = FALSE")
        path.unlink()

    copier_dans_raw = SQLExecuteQueryOperator(
        task_id="copier_dans_raw",
        conn_id=CONN_ID,
        sql="""
            COPY INTO NYC_TAXI.RAW.YELLOW_TRIPDATA
            FROM @NYC_TAXI.RAW.TLC_STAGE
            FILES = ('yellow_tripdata_{{ logical_date.strftime("%Y-%m") }}.parquet')
            FILE_FORMAT = (FORMAT_NAME = NYC_TAXI.RAW.FF_PARQUET)
            MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
            INCLUDE_METADATA = (_source_file = METADATA$FILENAME,
                                _loaded_at   = METADATA$START_SCAN_TIME)
        """,
    )

    # ---------- Contrôle du chargement (fourni) ----------
    raw_mois_charge = controle("controles/raw_mois_charge.sql")

    # ---------- Tables alimentées mois par mois ----------
    tables_mensuelles = sql_task("00_tables.sql")

    # ---------- STAGING : renommage et tables de codes ----------
    with TaskGroup("staging") as staging:
        sql_task("staging/stg_tlc__yellow_trips.sql")
        sql_task("staging/stg_tlc__taxi_zones.sql")
        sql_task("staging/codes_tlc.sql")

    # ---------- INTERMEDIATE : étiquetage puis trajets valides ----------
    with TaskGroup("intermediate") as intermediate:
        sql_task("intermediate/int_trips__flagged.sql") >> sql_task(
            "intermediate/int_trips__enriched.sql"
        )

    # ---------- Contrôles qualité : avant d'alimenter les marts ----------
    with TaskGroup("controles_qualite") as controles_qualite:
        controle("controles/trajets_sans_doublon.sql")
        controle("controles/taux_rejet.sql")

    # ---------- MARTS : dimensions, faits, analyses ----------
    with TaskGroup("marts") as marts:
        dim_date = sql_task("marts/dim_date.sql")
        dim_payment_type = sql_task("marts/dim_payment_type.sql")
        sql_task("marts/dim_rate_code.sql")
        sql_task("marts/dim_vendor.sql")
        dim_zone = sql_task("marts/dim_zone.sql")
        fct_trips = sql_task("marts/fct_trips.sql")
        sql_task("marts/mart_data_quality.sql")
        [fct_trips, dim_date, dim_payment_type] >> sql_task("marts/mart_daily_revenue.sql")
        [fct_trips, dim_zone] >> sql_task("marts/mart_zone_hourly_demand.sql")

    # ---------- Enchaînement général ----------
    (
        telecharger_et_deposer(verifier_fichier(MOIS))
        >> copier_dans_raw
        >> raw_mois_charge
        >> tables_mensuelles
        >> staging
        >> intermediate
        >> controles_qualite
        >> marts
    )


nyc_taxi_chargement()