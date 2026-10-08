-- =====================================================================
-- credits.sql
-- Mesurer les crédits consommés par le projet (critère C16).
--
-- COMMENT SNOWFLAKE FACTURE LE CALCUL
-- - En crédits, uniquement quand un warehouse est allumé, qu'il travaille ou non.
-- - Warehouse XS = 1 crédit par heure allumé, facturé à la seconde, avec un
--   minimum de 60 secondes à chaque démarrage. Chaque taille au-dessus double le coût.
-- - NYC_TAXI_WH : XS, AUTO_SUSPEND = 60 s, AUTO_RESUME = TRUE
--   (voir 01_infrastructure.sql). Un mois complet du pipeline tourne en moins
--   d'une minute : XS suffit largement.
--
-- POURQUOI ACCOUNTADMIN
-- L'historique de consommation est dans SNOWFLAKE.ACCOUNT_USAGE, réservé aux
-- administrateurs du compte. C'est une requête d'administration, lancée par
-- une personne, jamais par les outils : le rôle TRANSFORMER n'y a pas accès.
-- Les chiffres peuvent avoir jusqu'à 3 heures de retard.
-- =====================================================================

USE ROLE ACCOUNTADMIN;


-- ---------------------------------------------------------------------
-- 1. Crédits consommés par warehouse et par jour (requête des ressources)
-- WAREHOUSE_METERING_HISTORY : une ligne par warehouse et par heure.
-- On regroupe par jour pour voir le coût de chaque journée de travail.
-- Fenêtre de 30 jours pour couvrir tout le projet.
-- ---------------------------------------------------------------------
SELECT
    warehouse_name,
    DATE(start_time)              AS jour,
    ROUND(SUM(credits_used), 3)   AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 2, 1;


-- ---------------------------------------------------------------------
-- 2. Total par warehouse sur le projet
-- Le chiffre à présenter : combien a coûté tout le projet.
-- credits_calcul : le warehouse allumé.
-- credits_services_cloud : métadonnées, compilation des requêtes... (facturés
-- seulement au-delà de 10 % du calcul quotidien).
-- heures_actives : nombre d'heures où le warehouse a été allumé au moins un peu.
-- ---------------------------------------------------------------------
SELECT
    warehouse_name,
    ROUND(SUM(credits_used), 3)                    AS credits_total,
    ROUND(SUM(credits_used_compute), 3)            AS credits_calcul,
    ROUND(SUM(credits_used_cloud_services), 3)     AS credits_services_cloud,
    COUNT(*)                                       AS heures_actives
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY credits_total DESC;
-- RÉSULTATS (projet du 5 au 8 octobre 2026) :
--   warehouse                   crédits   heures actives
--   COMPUTE_WH (par défaut)       1,515         11
--   NYC_TAXI_WH (pipeline)        0,507          9
--   SALES_WH (guide du jour 1)    0,022          2
-- Lecture :
-- - Tout le pipeline, développement et tests compris (chargements, transformations,
--   relances, test d'échec), a coûté 0,5 crédit : XS + extinction après 60 s.
-- - COMPUTE_WH, créé automatiquement avec le compte d'essai, a coûté 3 fois plus
--   que le pipeline sans faire partie du projet (voir section 4).


-- ---------------------------------------------------------------------
-- 3. Vérifier la configuration qui limite les coûts
-- ---------------------------------------------------------------------
SHOW WAREHOUSES LIKE 'NYC_TAXI_WH';
-- Résultat : size = X-Small, auto_suspend = 60, auto_resume = true,
-- state = SUSPENDED (éteint quand il ne sert pas : il ne coûte rien).


-- ---------------------------------------------------------------------
-- 4. Enquête : pourquoi COMPUTE_WH a-t-il coûté plus que le pipeline ?
-- Hypothèse : c'est le warehouse par défaut de l'utilisateur personnel dans
-- Snowsight. Les requêtes manuelles lancées sans USE WAREHOUSE tournaient
-- dessus, et il restait allumé longtemps après chacune.
-- ---------------------------------------------------------------------
SHOW WAREHOUSES LIKE 'COMPUTE_WH';
-- Résultat : auto_suspend = 300 (5 minutes, contre 60 s pour NYC_TAXI_WH),
-- is_default = Y, et state = STARTED pendant que cette requête tournait.
-- Hypothèse confirmée : chaque requête manuelle, même de 2 secondes, le
-- laissait allumé 5 minutes pour rien.


-- ---------------------------------------------------------------------
-- 5. Correction appliquée
-- ---------------------------------------------------------------------
ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 60;                   -- s'éteint après 60 s
ALTER USER <TON_UTILISATEUR> SET DEFAULT_WAREHOUSE = NYC_TAXI_WH;   -- requêtes manuelles sur NYC_TAXI_WH
ALTER WAREHOUSE COMPUTE_WH SUSPEND;                                 -- éteint immédiatement


-- =====================================================================
-- CONCLUSIONS
-- 1. Le pipeline complet coûte très peu : 0,5 crédit pour tout le projet.
-- 2. On paie tant qu'un warehouse est allumé, qu'il travaille ou non :
--    l'extinction automatique est le réglage qui pèse le plus sur la facture.
-- 3. Un warehouse hors projet, resté avec ses réglages par défaut, a coûté
--    3 fois plus que le pipeline. Mesurer la consommation a permis de le
--    repérer, de comprendre pourquoi et de corriger.
-- =====================================================================