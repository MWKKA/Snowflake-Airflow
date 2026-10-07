"""Charge un mois de trajets des taxis jaunes, ou la liste des zones, dans NYC_TAXI.RAW.

Usage :
    python ingestion/load_month.py --month 2025-01
    python ingestion/load_month.py --zones
"""
import argparse
import os
import tempfile
from datetime import datetime
from pathlib import Path

import requests
import snowflake.connector

BASE_URL = "https://d37ci6vzurychx.cloudfront.net"
STAGE = "@NYC_TAXI.RAW.TLC_STAGE"
DOWNLOAD_DIR = Path(tempfile.gettempdir()) / "nyc_taxi"   # /tmp/nyc_taxi, hors du dépôt Git


def get_connection():
    """Connexion par paire de clés : aucun secret dans le code."""
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="SNOWFLAKE_JWT",
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        role="TRANSFORMER",
        warehouse="NYC_TAXI_WH",
        database="NYC_TAXI",
        schema="RAW",
    )


def download(url: str) -> Path:
    """Télécharge le fichier une seule fois, par morceaux, pour ne pas saturer la mémoire."""
    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    path = DOWNLOAD_DIR / url.rsplit("/", 1)[-1]
    if path.exists():
        print(f"Déjà téléchargé : {path}")
        return path
    print(f"Téléchargement de {url}")
    tmp = path.with_suffix(path.suffix + ".part")   # fichier incomplet tant que pas fini
    with requests.get(url, stream=True, timeout=60) as r:
        r.raise_for_status()                         # erreur claire si le mois n'existe pas
        with open(tmp, "wb") as f:
            for chunk in r.iter_content(chunk_size=1024 * 1024):
                f.write(chunk)
    tmp.rename(path)
    return path


def put(cur, path: Path):
    """Dépose le fichier à la racine du stage, sans le recompresser (nom conservé)."""
    cur.execute(f"PUT 'file://{path}' {STAGE} AUTO_COMPRESS = FALSE")
    print("PUT :", cur.fetchone()[6])                # UPLOADED, ou SKIPPED s'il y est déjà


def load_trips(cur, month: str):
    datetime.strptime(month, "%Y-%m")                # refuse tout ce qui n'est pas AAAA-MM
    file_name = f"yellow_tripdata_{month}.parquet"
    put(cur, download(f"{BASE_URL}/trip-data/{file_name}"))
    cur.execute(f"""
        COPY INTO YELLOW_TRIPDATA
        FROM {STAGE}
        FILES = ('{file_name}')
        FILE_FORMAT = (FORMAT_NAME = FF_PARQUET)
        MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
        INCLUDE_METADATA = (_source_file = METADATA$FILENAME,
                            _loaded_at   = METADATA$START_SCAN_TIME)
    """)
    print("COPY :", cur.fetchall())
    n = cur.execute(
        "SELECT COUNT(*) FROM YELLOW_TRIPDATA WHERE _source_file = %s", (file_name,)
    ).fetchone()[0]
    print(f"{file_name} : {n} lignes dans RAW.YELLOW_TRIPDATA")


def load_zones(cur):
    file_name = "taxi_zone_lookup.csv"
    put(cur, download(f"{BASE_URL}/misc/{file_name}"))
    cur.execute(f"""
        COPY INTO TAXI_ZONE_LOOKUP (locationid, borough, zone, service_zone, _source_file, _loaded_at)
        FROM (SELECT $1, $2, $3, $4, METADATA$FILENAME, METADATA$START_SCAN_TIME FROM {STAGE})
        FILES = ('{file_name}')
        FILE_FORMAT = (FORMAT_NAME = FF_CSV)
    """)
    print("COPY :", cur.fetchall())
    n = cur.execute("SELECT COUNT(*) FROM TAXI_ZONE_LOOKUP").fetchone()[0]
    print(f"{n} zones dans RAW.TAXI_ZONE_LOOKUP")


def main():
    parser = argparse.ArgumentParser(description="Chargement TLC vers NYC_TAXI.RAW")
    choix = parser.add_mutually_exclusive_group(required=True)
    choix.add_argument("--month", help="mois à charger, format AAAA-MM (ex. 2025-01)")
    choix.add_argument("--zones", action="store_true", help="charger la liste des zones")
    args = parser.parse_args()

    conn = get_connection()
    try:
        cur = conn.cursor()
        if args.zones:
            load_zones(cur)
        else:
            load_trips(cur, args.month)
    finally:
        conn.close()                                 # on ferme même en cas d'erreur


if __name__ == "__main__":
    main()