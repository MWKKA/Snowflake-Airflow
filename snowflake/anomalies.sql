-- =====================================================================
-- anomalies.sql
-- Compter nous-mêmes les trajets anormaux d'un mois (janvier 2025) et
-- comparer avec MARTS.MART_DATA_QUALITY.
--
-- DEUX FAÇONS DE COMPTER
-- - MART_DATA_QUALITY : chaque trajet reçoit AU PLUS UNE raison de rejet,
--   la PREMIÈRE règle qui échoue, dans l'ordre du CASE de int_trips__flagged.
-- - Ici : chaque anomalie est comptée INDÉPENDAMMENT. Un trajet à la fois de
--   distance nulle et de montant négatif est compté dans les deux colonnes.
-- Conséquences attendues :
-- - nos comptages par règle seront >= ceux du mart ;
-- - la SOMME de nos comptages dépassera le total des rejets (chevauchements) ;
-- - mais le nombre de trajets avec AU MOINS UNE anomalie doit être ÉGAL au
--   total des rejets du mart (223 889) : c'est la vraie vérification.
--
-- Pourquoi partir de RAW ? Pour un calcul INDÉPENDANT du pipeline : si on
-- retombe sur ses chiffres en partant des données brutes, les deux se confirment.
-- =====================================================================

USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;


-- ---------------------------------------------------------------------
-- 1. Chaque anomalie comptée indépendamment, sur RAW
-- Mêmes règles et mêmes seuils que int_trips__flagged :
-- 180 minutes de durée maximale, 100 miles de distance maximale.
-- La CTE « t » renomme les colonnes brutes pour lire les règles plus facilement.
-- ---------------------------------------------------------------------
WITH t AS (
    SELECT
        tpep_pickup_datetime   AS pickup_at,
        tpep_dropoff_datetime  AS dropoff_at,
        trip_distance,
        fare_amount,
        total_amount,
        pulocationid,
        dolocationid
    FROM NYC_TAXI.RAW.YELLOW_TRIPDATA
    WHERE _source_file = 'yellow_tripdata_2025-01.parquet'
)
SELECT
    COUNT(*)                                                             AS trajets,
    COUNT_IF(pickup_at IS NULL OR dropoff_at IS NULL)                    AS timestamp_null,
    COUNT_IF(dropoff_at <= pickup_at)                                    AS duration_non_positive,
    COUNT_IF(DATEDIFF('second', pickup_at, dropoff_at) > 180 * 60)       AS duration_too_long,
    COUNT_IF(DATE_TRUNC('month', pickup_at) <> '2025-01-01'::date)       AS pickup_outside_file_month,
    COUNT_IF(trip_distance <= 0 OR trip_distance > 100)                  AS distance_out_of_range,
    COUNT_IF(fare_amount < 0 OR total_amount <= 0)                       AS amount_non_positive,
    COUNT_IF(pulocationid IS NULL OR dolocationid IS NULL)               AS zone_null,
    -- au moins une anomalie : doit être égal au total des rejets du mart
    COUNT_IF(
           pickup_at IS NULL OR dropoff_at IS NULL
        OR dropoff_at <= pickup_at
        OR DATEDIFF('second', pickup_at, dropoff_at) > 180 * 60
        OR DATE_TRUNC('month', pickup_at) <> '2025-01-01'::date
        OR trip_distance <= 0 OR trip_distance > 100
        OR fare_amount < 0 OR total_amount <= 0
        OR pulocationid IS NULL OR dolocationid IS NULL
    )                                                                    AS au_moins_une_anomalie
FROM t;
-- RÉSULTAT (janvier 2025) et COMPARAISON avec MART_DATA_QUALITY :
--   règle (ordre du CASE)       nous (indépendant)   mart (1re règle)   écart
--   timestamp_null                       0                  —              0
--   duration_non_positive            2 051              2 051              0
--   duration_too_long                1 377              1 377              0
--   pickup_outside_file_month           22                 22              0
--   distance_out_of_range           91 055             90 327            728
--   amount_non_positive            144 998            130 112         14 886
--   zone_null                            0                  —              0
--   AU MOINS UNE ANOMALIE          223 889            223 889              0
-- Lecture :
-- - Le total est identique : pipeline et calcul indépendant rejettent les mêmes trajets.
-- - Les écarts n'apparaissent qu'en fin de CASE : ces trajets cumulent plusieurs
--   anomalies et le mart les a classés sous une règle antérieure.
-- - Somme de nos comptages = 239 503 ; 239 503 - 223 889 = 15 614 = 728 + 14 886.
--   Les chevauchements expliquent l'écart au trajet près (voir requête 2).
-- - timestamp_null et zone_null valent 0 : c'est pourquoi le mart n'a pas de
--   ligne pour ces motifs (un GROUP BY ne crée une ligne que pour les valeurs présentes).


-- ---------------------------------------------------------------------
-- 2. Combien d'anomalies par trajet ?
-- Explique l'écart : si des trajets cumulent plusieurs anomalies,
-- la somme de nos comptages dépasse le nombre de trajets rejetés.
-- Astuce : (condition)::int vaut 1 si vraie, 0 sinon ; on additionne.
-- COALESCE(..., FALSE) : si une colonne est NULL, la condition vaut NULL,
-- qu'on traite comme « pas d'anomalie » pour cette règle (sinon 1 + NULL = NULL).
-- (timestamp_null et zone_null sont omises : la requête 1 montre qu'elles valent 0.)
-- ---------------------------------------------------------------------
WITH t AS (
    SELECT
        tpep_pickup_datetime   AS pickup_at,
        tpep_dropoff_datetime  AS dropoff_at,
        trip_distance, fare_amount, total_amount
    FROM NYC_TAXI.RAW.YELLOW_TRIPDATA
    WHERE _source_file = 'yellow_tripdata_2025-01.parquet'
),
nb AS (
    SELECT
          COALESCE(dropoff_at <= pickup_at, FALSE)::int                               -- durée nulle ou négative
        + COALESCE(DATEDIFF('second', pickup_at, dropoff_at) > 180 * 60, FALSE)::int  -- durée > 3 h
        + COALESCE(DATE_TRUNC('month', pickup_at) <> '2025-01-01'::date, FALSE)::int  -- hors du mois
        + COALESCE(trip_distance <= 0 OR trip_distance > 100, FALSE)::int             -- distance anormale
        + COALESCE(fare_amount < 0 OR total_amount <= 0, FALSE)::int  AS nb_anomalies -- montant anormal
    FROM t
)
SELECT nb_anomalies, COUNT(*) AS trajets
FROM nb
GROUP BY 1
ORDER BY 1;
-- RÉSULTAT (janvier 2025) :
--   nb_anomalies    trajets
--        0        3 251 337   = trajets « valid » du mart
--        1          208 313
--        2           15 538
--        3               38
-- Vérifications :
-- - 208 313 + 15 538 + 38 = 223 889 = total des rejets du mart.
-- - Surplus de nos comptages indépendants : 15 538 × 1 + 38 × 2 = 15 614
--   = 728 + 14 886, l'écart trouvé à la requête 1. Les chevauchements
--   expliquent la différence avec le mart au trajet près.
-- - 93,5 % des trajets n'ont aucune anomalie ; parmi les rejetés, 93 % n'en ont
--   qu'une. Ceux qui en cumulent plusieurs sont surtout des courses annulées
--   (durée, distance et montant à zéro).