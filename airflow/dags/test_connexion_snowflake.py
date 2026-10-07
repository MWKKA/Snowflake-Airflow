"""Prouve qu'Airflow se connecte à Snowflake avec la clé du .env, sans secret dans le code."""
from airflow.sdk import dag
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from pendulum import datetime


@dag(
    schedule=None,                      # ne tourne que si on le lance à la main
    start_date=datetime(2025, 1, 1),
    catchup=False,
    tags=["test"],
)
def test_connexion_snowflake():
    SQLExecuteQueryOperator(
        task_id="qui_suis_je",
        conn_id="snowflake_nyc_taxi",   # la connexion déclarée dans .env
        sql="SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE()",
        show_return_value_in_logs=True, # affiche le résultat dans les logs
    )


test_connexion_snowflake()