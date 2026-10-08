-- =====================================================================
-- droits.sql
-- Vérifier les droits du rôle des outils (critère C16) :
-- 1. ce qu'il PEUT faire : ses droits, et qui le possède ;
-- 2. ce qu'il ne PEUT PAS faire : des accès hors périmètre, qui doivent échouer.
--
-- PRINCIPE : le moindre privilège. TRANSFORMER reçoit uniquement ce que le
-- contrat exige (charger RAW, créer tables et vues dans les 3 autres schémas).
-- Si la clé d'Airflow fuitait, les dégâts resteraient limités à NYC_TAXI.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Ce que le rôle PEUT faire
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;

-- Les droits du rôle
SHOW GRANTS TO ROLE TRANSFORMER;
-- Résultat attendu :
-- - USAGE sur le warehouse NYC_TAXI_WH et la base NYC_TAXI ;
-- - USAGE + CREATE TABLE, CREATE STAGE, CREATE FILE FORMAT sur RAW ;
-- - USAGE + CREATE TABLE, CREATE VIEW sur STAGING, INTERMEDIATE, MARTS ;
-- - OWNERSHIP sur les objets qu'il a créés (tables, vues, stage, formats).
-- Aucun droit sur une autre base, aucun droit au niveau du compte.

-- Qui possède le rôle
SHOW GRANTS OF ROLE TRANSFORMER;
-- Résultat attendu : l'utilisateur de service AIRFLOW_SVC, l'utilisateur
-- personnel (pour tester) et le rôle SYSADMIN (hiérarchie : l'administrateur
-- garde la main sur les objets du rôle).

-- Les rôles de l'utilisateur de service
SHOW GRANTS TO USER AIRFLOW_SVC;
-- Résultat attendu : uniquement TRANSFORMER.


-- ---------------------------------------------------------------------
-- 2. Ce que le rôle NE PEUT PAS faire
-- On se place EXACTEMENT dans la situation d'Airflow :
-- - USE ROLE TRANSFORMER : le rôle des outils ;
-- - USE SECONDARY ROLES NONE : sans cela, la session personnelle emprunterait
--   les droits des autres rôles de l'utilisateur (ACCOUNTADMIN, SYSADMIN...)
--   et certains tests réussiraient à tort.
--
-- Chaque test ci-dessous DOIT ÉCHOUER. Les lancer UN PAR UN (Ctrl+Entrée) :
-- avec Run All, Snowsight s'arrêterait à la première erreur.
-- ---------------------------------------------------------------------
USE ROLE TRANSFORMER;
USE SECONDARY ROLES NONE;
USE WAREHOUSE NYC_TAXI_WH;

-- 2.a Créer une base : droit de niveau compte, non accordé
CREATE DATABASE TEST_INTERDIT;
-- Résultat : REFUSÉ. « Insufficient privileges to operate on account.
-- Your primary role TRANSFORMER must have CREATE DATABASE granted on ACCOUNT. »

-- 2.b Lire une autre base du compte (celle du guide du jour 1)
SELECT * FROM SALES_DB.RAW_DATA.ORDERS LIMIT 1;
-- Résultat : REFUSÉ. « Database 'SALES_DB' does not exist or not authorized. »
-- Snowflake ne dit même pas si la base existe : il ne révèle rien hors périmètre.

-- 2.c Supprimer la base du projet
DROP DATABASE NYC_TAXI;
-- Résultat : REFUSÉ. « Insufficient privileges to operate on database 'NYC_TAXI'.
-- Your primary role TRANSFORMER must have OWNERSHIP granted on DATABASE NYC_TAXI. »
-- Même avec la clé d'Airflow, on ne peut pas détruire le projet.

-- ---------------------------------------------------------------------
-- 3. Remettre la session dans son état normal
-- ---------------------------------------------------------------------
USE SECONDARY ROLES ALL;
USE ROLE SYSADMIN;


-- =====================================================================
-- CONCLUSIONS
-- - TRANSFORMER a exactement les droits du contrat, ni plus ni moins.
-- - Les accès hors périmètre sont refusés : créer une base, lire une autre
--   base, supprimer la base du projet.
-- - Les outils (script Python, Airflow) se connectent avec AIRFLOW_SVC, qui
--   n'a que ce rôle : jamais ACCOUNTADMIN.
-- =====================================================================