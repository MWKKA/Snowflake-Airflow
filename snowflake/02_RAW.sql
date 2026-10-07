-- =====================================================
-- 02_raw.sql : couche RAW (formats, stage, tables)
-- Exécuté avec le rôle des outils : TRANSFORMER devient
-- propriétaire des objets, comme l'exige le contrat.
-- =====================================================
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;
USE SCHEMA NYC_TAXI.RAW;

-- Formats de fichier
CREATE FILE FORMAT IF NOT EXISTS FF_PARQUET
  TYPE = PARQUET
  USE_LOGICAL_TYPE = TRUE;          -- lit les dates Parquet comme des dates, pas comme des nombres

CREATE FILE FORMAT IF NOT EXISTS FF_CSV
  TYPE = CSV
  SKIP_HEADER = 1                   -- la 1re ligne contient les noms de colonnes
  FIELD_OPTIONALLY_ENCLOSED_BY = '"';

-- Stage interne : zone de dépôt des fichiers avant COPY INTO
CREATE STAGE IF NOT EXISTS TLC_STAGE
  COMMENT = 'Fichiers TLC déposés par PUT, à la racine du stage';

-- Trajets : copie fidèle des fichiers Parquet mensuels
CREATE TABLE IF NOT EXISTS YELLOW_TRIPDATA (
  vendorid               NUMBER,
  tpep_pickup_datetime   TIMESTAMP_NTZ,
  tpep_dropoff_datetime  TIMESTAMP_NTZ,
  passenger_count        NUMBER,
  trip_distance          FLOAT,
  ratecodeid             NUMBER,
  store_and_fwd_flag     VARCHAR,
  pulocationid           NUMBER,
  dolocationid           NUMBER,
  payment_type           NUMBER,
  fare_amount            FLOAT,
  extra                  FLOAT,
  mta_tax                FLOAT,
  tip_amount             FLOAT,
  tolls_amount           FLOAT,
  improvement_surcharge  FLOAT,
  total_amount           FLOAT,
  congestion_surcharge   FLOAT,
  airport_fee            FLOAT,
  cbd_congestion_fee     FLOAT,
  _source_file           VARCHAR,        -- colonne technique : nom du fichier chargé
  _loaded_at             TIMESTAMP_NTZ   -- colonne technique : date du chargement
);

-- Zones : référentiel des 265 zones de taxi
CREATE TABLE IF NOT EXISTS TAXI_ZONE_LOOKUP (
  locationid    NUMBER,
  borough       VARCHAR,
  zone          VARCHAR,
  service_zone  VARCHAR,
  _source_file  VARCHAR,
  _loaded_at    TIMESTAMP_NTZ
);

-- Vérification : la colonne owner doit afficher TRANSFORMER
SHOW TABLES IN SCHEMA NYC_TAXI.RAW;