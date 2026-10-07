"""Chargement mensuel des trajets TLC dans NYC_TAXI.RAW.YELLOW_TRIPDATA.

Une exécution = un mois. Le mois est déduit de la date logique de l'exécution,
jamais de la date du jour : c'est ce qui permet de rejouer janvier, février et mars.
"""
import tempfile
from datetime import timedelta
from pathlib import Path

import requests
from airflow.sdk import dag, task
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from pendulum import datetime

CONN_ID = "snowflake_nyc_taxi"
BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data"
STAGE = "@NYC_TAXI.RAW.TLC_STAGE"

# Modèle Jinja : Airflow le remplace par le mois de l'exécution (ex. 2025-01)
MOIS = "{{ logical_date.strftime('%Y-%m') }}"


@dag(
    schedule="@monthly",                 # une exécution par mois
    start_date=datetime(2025, 1, 1),     # premier mois traité : janvier 2025
    end_date=datetime(2025, 3, 31),      # dernier mois traité : mars 2025
    catchup=True,                        # rejoue les mois passés (False par défaut en Airflow 3)
    max_active_runs=1,                   # un mois à la fois
    default_args={
        "retries": 2,                            # relances automatiques
        "retry_delay": timedelta(minutes=2),
    },
    tags=["nyc_taxi"],
)
def nyc_taxi_chargement():

    @task
    def verifier_fichier(mois: str) -> str:
        """Vérifie que la TLC a publié le fichier du mois, sans le télécharger."""
        url = f"{BASE_URL}/yellow_tripdata_{mois}.parquet"
        r = requests.head(url, timeout=30)
        if r.status_code != 200:
            raise ValueError(f"Fichier indisponible (HTTP {r.status_code}) : {url}")
        print(f"Fichier disponible : {url}")
        return url

    @task
    def telecharger_et_deposer(url: str) -> None:
        """Télécharge le fichier puis l'envoie à la racine du stage (PUT)."""
        path = Path(tempfile.gettempdir()) / url.rsplit("/", 1)[-1]
        with requests.get(url, stream=True, timeout=60) as r:
            r.raise_for_status()
            with open(path, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024 * 1024):
                    f.write(chunk)
        hook = SnowflakeHook(snowflake_conn_id=CONN_ID)
        with hook.get_conn() as conn:
            cur = conn.cursor()
            cur.execute(f"PUT 'file://{path}' {STAGE} AUTO_COMPRESS = FALSE")
            print("PUT :", cur.fetchone())
        path.unlink()                        # on ne garde pas les 60 Mo sur le disque

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
        show_return_value_in_logs=True,
    )

    telecharger_et_deposer(verifier_fichier(MOIS)) >> copier_dans_raw


nyc_taxi_chargement()