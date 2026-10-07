-- =====================================================
-- verif_contrat_raw.sql : vérifie que la couche RAW
-- respecte CONTRAT_RAW.md. Ne modifie rien.
-- À lancer après un chargement, avec le rôle des outils.
-- =====================================================
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- 1. Les deux tables appartiennent à TRANSFORMER (colonne owner)
SHOW TABLES IN SCHEMA NYC_TAXI.RAW;

-- 2. Colonnes techniques remplies
SELECT _source_file, COUNT(*), MIN(_loaded_at)
FROM NYC_TAXI.RAW.YELLOW_TRIPDATA GROUP BY 1;

-- 3. Les montants ont gardé leurs décimales
SELECT fare_amount, total_amount, tpep_pickup_datetime
FROM NYC_TAXI.RAW.YELLOW_TRIPDATA LIMIT 5;

-- 4. Les zones
SELECT * FROM NYC_TAXI.RAW.TAXI_ZONE_LOOKUP LIMIT 5;