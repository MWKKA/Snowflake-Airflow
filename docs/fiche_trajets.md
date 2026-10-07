# Fiche source — Trajets des taxis jaunes de New York (Yellow Taxi Trip Records)

## Identité

| Rubrique | Réponse |
|---|---|
| Nom de la source | Yellow Taxi Trip Records |
| Producteur des données | NYC Taxi and Limousine Commission (TLC), à partir des données transmises par les fournisseurs de taximètres (TPEP) |
| Adresse (URL) | `https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_AAAA-MM.parquet` (ex. `yellow_tripdata_2025-01.parquet`) |
| Accès (public, authentifié) | Public, sans authentification |
| Format du fichier | Apache Parquet (colonnes typées, compressé) |
| Fréquence de publication | Mensuelle : un fichier par mois |
| Délai entre la période couverte et la publication | Fichier de janvier 2025 mis en ligne (ou republié) le 23 avril 2025, soit environ 12 semaines après la fin du mois. Mesuré avec l'en-tête HTTP `Last-Modified`, qui indique la dernière mise en ligne du fichier |

## Volume mesuré

| Fichier | Taille | Nombre de lignes | Nombre de colonnes | Outil et commande utilisés |
|---|---|---|---|---|
| `yellow_tripdata_2025-01.parquet` | 56,4 Mo | 3 475 226 | 20 | DuckDB : `uv run --with duckdb python ingestion/explorer_fichier.py <fichier>` |
| Même mois, chargé dans `NYC_TAXI.RAW.YELLOW_TRIPDATA` | 89 Mo (stockage Snowflake) | 3 475 226 | 22 (20 + 2 colonnes techniques) | `SHOW TABLES IN SCHEMA NYC_TAXI.RAW` |
| `yellow_tripdata_2025-02.parquet` | — | 3 577 543 | 20 | comptage dans Snowflake après chargement par Airflow |
| `yellow_tripdata_2025-03.parquet` | — | 4 145 257 | 20 | comptage dans Snowflake après chargement par Airflow |

## Colonnes

| Colonne | Type dans le fichier | Signification | Exemple de valeur |
|---|---|---|---|
| VendorID | INTEGER | Fournisseur du taximètre qui a transmis le trajet | 1 |
| tpep_pickup_datetime | TIMESTAMP | Date et heure de mise en marche du compteur (prise en charge) | 2025-01-01 00:18:38 |
| tpep_dropoff_datetime | TIMESTAMP | Date et heure d'arrêt du compteur (dépose) | 2025-01-01 00:26:59 |
| passenger_count | BIGINT | Nombre de passagers, saisi par le chauffeur | 1 |
| trip_distance | DOUBLE | Distance parcourue en miles, mesurée par le taximètre | 1.6 |
| RatecodeID | BIGINT | Code du tarif appliqué en fin de trajet | 1 |
| store_and_fwd_flag | VARCHAR | Trajet stocké dans le véhicule avant envoi, faute de connexion | N |
| PULocationID | INTEGER | Zone TLC de prise en charge (voir `taxi_zone_lookup.csv`) | 229 |
| DOLocationID | INTEGER | Zone TLC de dépose | 237 |
| payment_type | BIGINT | Mode de paiement | 1 |
| fare_amount | DOUBLE | Prix de la course calculé par le compteur (temps et distance), en dollars | 10.0 |
| extra | DOUBLE | Suppléments divers (heures de pointe, nuit) | 3.5 |
| mta_tax | DOUBLE | Taxe MTA, déclenchée automatiquement selon le tarif | 0.5 |
| tip_amount | DOUBLE | Pourboire payé par carte (les pourboires en espèces ne sont pas enregistrés) | 3.0 |
| tolls_amount | DOUBLE | Total des péages | 0.0 |
| improvement_surcharge | DOUBLE | Surcharge d'amélioration appliquée à la prise en charge | 1.0 |
| total_amount | DOUBLE | Montant total payé, hors pourboires en espèces | 18.0 |
| congestion_surcharge | DOUBLE | Surcharge de congestion de l'État de New York | 2.5 |
| Airport_fee | DOUBLE | Frais de prise en charge aux aéroports JFK et LaGuardia | 0.0 |
| cbd_congestion_fee | DOUBLE | Péage urbain de la zone de congestion de Manhattan, en vigueur depuis le 5 janvier 2025 | 0.0 |

## Codes

Valeurs d'après le dictionnaire de données TLC ; entre parenthèses, le nombre de trajets mesuré en janvier 2025.

| Colonne | Valeur | Signification |
|---|---|---|
| VendorID | 1 | Creative Mobile Technologies, LLC (753 671) |
| VendorID | 2 | Curb Mobility, LLC (2 719 860) |
| VendorID | 6 | Myle Technologies Inc (489) |
| VendorID | 7 | Helix (1 206) |
| RatecodeID | 1 | Tarif standard (2 756 472) |
| RatecodeID | 2 | Aéroport JFK (94 420) |
| RatecodeID | 3 | Aéroport de Newark (8 622) |
| RatecodeID | 4 | Nassau ou Westchester (7 092) |
| RatecodeID | 5 | Tarif négocié (26 501) |
| RatecodeID | 6 | Course groupée (7) |
| RatecodeID | 99 | Inconnu (41 963) |
| RatecodeID | vide | Non renseigné (540 149) |
| payment_type | 0 | Trajet « Flex Fare » (540 149) |
| payment_type | 1 | Carte bancaire (2 444 393) |
| payment_type | 2 | Espèces (390 429) |
| payment_type | 3 | Gratuit (23 773) |
| payment_type | 4 | Litige (76 481) |
| payment_type | 5 | Inconnu (1) |
| payment_type | 6 | Trajet annulé (absent en janvier) |
| store_and_fwd_flag | Y | Trajet stocké puis transmis plus tard (7 646) |
| store_and_fwd_flag | N | Trajet transmis directement (2 927 431) |
| store_and_fwd_flag | vide | Non renseigné (540 149) |

## Ce qui a surpris

- **540 149 trajets (15,5 %) ont plusieurs champs vides en même temps** (`passenger_count`, `RatecodeID`, `store_and_fwd_flag`) et un `payment_type` à 0 : un même lot d'enregistrements incomplets.
- **Des valeurs impossibles** : 90 893 distances nulles ou négatives (2,6 %), 63 037 montants totaux négatifs (1,8 %), 124 trajets qui arrivent avant d'être partis.
- **22 trajets hors du mois**, dont un départ le 31 décembre 2024 à 20 h 47 et un le 1er février 2025 à 0 h 00 : un fichier « mensuel » ne contient pas que son mois.
- **Les types ne sont pas ceux qu'on attendrait** : `passenger_count` et `RatecodeID` sont des entiers longs, et `Airport_fee` prend une majuscule, contrairement aux autres colonnes.