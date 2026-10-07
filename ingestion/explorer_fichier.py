"""Explore un fichier de trajets TLC pour remplir la fiche source, avec des mesures réelles.

Usage :
    uv run --with duckdb python ingestion/explorer_fichier.py /tmp/nyc_taxi/yellow_tripdata_2025-01.parquet
"""
import os
import sys

import duckdb
import requests

path = sys.argv[1]
f = f"'{path}'"
nom = os.path.basename(path)

# Volume
print(f"Fichier : {nom}")
print(f"Taille : {os.path.getsize(path) / 1024**2:.1f} Mo")
print("Lignes :", duckdb.sql(f"SELECT COUNT(*) FROM {f}").fetchone()[0])

# Colonnes : nom, type dans le fichier, exemple (1re ligne)
types = duckdb.sql(f"DESCRIBE SELECT * FROM {f}").fetchall()
exemple = duckdb.sql(f"SELECT * FROM {f} LIMIT 1").fetchone()
print(f"\nColonnes ({len(types)}) : nom | type | exemple")
for (col, typ, *_), val in zip(types, exemple):
    print(f"  {col} | {typ} | {val}")

# Codes : valeurs réellement présentes et leur fréquence
for col in ["VendorID", "RatecodeID", "payment_type", "store_and_fwd_flag"]:
    print(f"\nCodes de {col} :")
    for val, n in duckdb.sql(f"SELECT {col}, COUNT(*) FROM {f} GROUP BY 1 ORDER BY 1").fetchall():
        print(f"  {val} : {n}")

# Anomalies
print("\nAnomalies :")
print(duckdb.sql(f"""
    SELECT
      MIN(tpep_pickup_datetime) AS premiere_prise,
      MAX(tpep_pickup_datetime) AS derniere_prise,
      COUNT(*) FILTER (WHERE tpep_pickup_datetime < DATE '2025-01-01'
                          OR tpep_pickup_datetime >= DATE '2025-02-01') AS hors_mois,
      COUNT(*) FILTER (WHERE trip_distance <= 0) AS distance_nulle,
      COUNT(*) FILTER (WHERE total_amount < 0) AS montant_negatif,
      COUNT(*) FILTER (WHERE tpep_dropoff_datetime < tpep_pickup_datetime) AS arrivee_avant_depart,
      COUNT(*) FILTER (WHERE passenger_count IS NULL) AS passagers_vides
    FROM {f}
"""))

# Délai de publication : date de mise en ligne du fichier sur le serveur
url = f"https://d37ci6vzurychx.cloudfront.net/trip-data/{nom}"
print("\nMis en ligne le :", requests.head(url, timeout=30).headers.get("Last-Modified"))