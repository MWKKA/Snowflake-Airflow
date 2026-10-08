-- =====================================================================
-- verif_pipeline.sql
-- Vérifie le résultat du pipeline : le nombre de lignes de chaque table,
-- de RAW jusqu'aux MARTS. Ne modifie rien.
--
-- À QUOI ÇA SERT
-- 1. Valider le pipeline : les comptages doivent correspondre à ceux du kit.
-- 2. Prouver la rejouabilité, pendant la démo :
--      a. lancer cette requête et noter les chiffres ;
--      b. relancer un mois dans Airflow (Clear Run > Clear existing tasks) ;
--      c. relancer cette requête : les chiffres doivent être IDENTIQUES.
--    Un seul chiffre qui augmente = des doublons = un pipeline non rejouable.
--
-- RÉSULTATS ATTENDUS (après janvier, février et mars 2025)
--   RAW.YELLOW_TRIPDATA               11 198 026
--   RAW.TAXI_ZONE_LOOKUP                     265
--   INTERMEDIATE.INT_TRIPS__FLAGGED   11 198 026   (= RAW : chaque trajet est
--                                                  étiqueté, aucun n'est perdu)
--   MARTS.FCT_TRIPS                   10 382 378   (trajets valides seulement)
--   MARTS.MART_ZONE_HOURLY_DEMAND         11 524
--   MARTS.MART_DATA_QUALITY                   18
--
-- LES CHIFFRES SE BOUCLENT
--   11 198 026 trajets bruts - 815 648 rejetés = 10 382 378 valides.
--   Les rejets par mois (6,44 %, 7,61 %, 7,71 %) sont mesurés par la
--   dernière requête ci-dessous.
-- =====================================================================

USE ROLE TRANSFORMER;            -- le rôle des outils : on voit ce que voit Airflow
USE WAREHOUSE NYC_TAXI_WH;


-- ---------------------------------------------------------------------
-- 1. Comptage de toutes les tables, en un seul tableau
-- UNION ALL empile les résultats de plusieurs SELECT qui ont les mêmes
-- colonnes. (UNION tout court supprimerait les lignes en double : inutile
-- ici, et plus lent.)
-- ---------------------------------------------------------------------
SELECT 'RAW.YELLOW_TRIPDATA'               AS table_name, COUNT(*) AS lignes FROM NYC_TAXI.RAW.YELLOW_TRIPDATA
UNION ALL SELECT 'RAW.TAXI_ZONE_LOOKUP',             COUNT(*) FROM NYC_TAXI.RAW.TAXI_ZONE_LOOKUP
UNION ALL SELECT 'INTERMEDIATE.INT_TRIPS__FLAGGED',  COUNT(*) FROM NYC_TAXI.INTERMEDIATE.INT_TRIPS__FLAGGED
UNION ALL SELECT 'MARTS.FCT_TRIPS',                  COUNT(*) FROM NYC_TAXI.MARTS.FCT_TRIPS
UNION ALL SELECT 'MARTS.MART_ZONE_HOURLY_DEMAND',    COUNT(*) FROM NYC_TAXI.MARTS.MART_ZONE_HOURLY_DEMAND
UNION ALL SELECT 'MARTS.MART_DATA_QUALITY',          COUNT(*) FROM NYC_TAXI.MARTS.MART_DATA_QUALITY;


-- ---------------------------------------------------------------------
-- 2. Détail par mois : chaque fichier chargé une seule fois
-- Si un mois apparaissait deux fois plus gros que prévu, ce serait un
-- doublon de chargement.
-- ---------------------------------------------------------------------
SELECT _source_file, COUNT(*) AS lignes
FROM NYC_TAXI.RAW.YELLOW_TRIPDATA
GROUP BY 1
ORDER BY 1;
-- Attendu : 2025-01 = 3 475 226 ; 2025-02 = 3 577 543 ; 2025-03 = 4 145 257.


-- ---------------------------------------------------------------------
-- 3. Taux de rejet par mois
-- Mesure ce que le contrôle taux_rejet vérifie dans Airflow. C'est cette
-- mesure qui a justifié le seuil de 15 % (environ deux fois le taux habituel).
-- ---------------------------------------------------------------------
SELECT
    source_file_month,
    COUNT(*)                                AS trajets,
    COUNT_IF(rejection_reason IS NOT NULL)  AS rejetes,
    ROUND(100 * rejetes / trajets, 2)       AS taux_rejet_pct
FROM NYC_TAXI.INTERMEDIATE.INT_TRIPS__FLAGGED
GROUP BY 1
ORDER BY 1;
-- Attendu : 6,44 % (janvier), 7,61 % (février), 7,71 % (mars).