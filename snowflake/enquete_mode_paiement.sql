-- =====================================================================
-- enquete_mode_paiement.sql
-- Enquête : les trajets payés par carte rapportent-ils vraiment plus ?
-- Et que valent les trajets « gratuits » ou « en litige » ?
--
-- POINT DE DÉPART (l'observation)
-- Dans le top 10, les trajets payés par carte affichent 4 à 6 $ de plus
-- que ceux payés en espèces. Conclusion tentante : « la carte rapporte
-- plus, il faut l'encourager ». Avant de l'écrire, on vérifie.
--
-- MÉTHODE : observer -> hypothèse -> tester -> conclure (ou reformuler)
-- =====================================================================

USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;


-- ---------------------------------------------------------------------
-- ÉTAPE 1 : vérifier ce que dit la documentation
-- Hypothèse : d'après le dictionnaire TLC, le pourboire n'est enregistré
-- que pour les paiements par carte (le terminal le voit, pas l'argent liquide).
-- Une documentation peut être fausse ou périmée : on la confronte aux données.
-- Test : pourboire moyen et part des trajets avec pourboire, par mode de paiement.
-- Ce qu'on cherche : un pourboire proche de 0 pour les espèces.
-- ---------------------------------------------------------------------
SELECT
    p.payment_type_label,
    COUNT(*)                                               AS nb_trajets,
    ROUND(AVG(f.tip_amount), 2)                            AS pourboire_moyen,
    ROUND(100 * COUNT_IF(f.tip_amount > 0) / COUNT(*), 1)  AS part_avec_pourboire_pct
FROM NYC_TAXI.MARTS.FCT_TRIPS f
JOIN NYC_TAXI.MARTS.DIM_PAYMENT_TYPE p
  ON p.payment_type_key = f.payment_type_key
GROUP BY 1
ORDER BY nb_trajets DESC;
-- Résultat : espèces = 0,00 $ de pourboire, sur 0,0 % des trajets (1 063 448 trajets).
--            carte    = 4,14 $ en moyenne, sur 94,1 % des trajets.
-- La documentation est confirmée. Et le pourboire moyen par carte (4,14 $)
-- est du même ordre que l'écart observé (4 à 6 $) : il pourrait tout expliquer.
-- Au passage : 1,77 million de trajets valides (17 %) sont en « Flex Fare »,
-- plus que les espèces.


-- ---------------------------------------------------------------------
-- ÉTAPE 2 : isoler le prix de la course
-- Hypothèse : les clients font les mêmes courses quel que soit leur mode de
-- paiement ; seul le pourboire, visible pour la carte, crée l'écart.
-- Test : comparer fare_amount (prix de la course SANS pourboire ni taxes)
-- et total_amount entre carte et espèces.
-- Si les prix de course sont proches, l'écart vient du pourboire.
-- ---------------------------------------------------------------------
SELECT
    p.payment_type_label,
    ROUND(AVG(f.fare_amount), 2)  AS prix_course_moyen,
    ROUND(AVG(f.total_amount), 2) AS montant_total_moyen
FROM NYC_TAXI.MARTS.FCT_TRIPS f
JOIN NYC_TAXI.MARTS.DIM_PAYMENT_TYPE p
  ON p.payment_type_key = f.payment_type_key
WHERE f.payment_type_key IN (1, 2)          -- 1 = carte, 2 = espèces
GROUP BY 1;
-- Résultat : prix de la course = 18,13 $ (carte) contre 18,06 $ (espèces).
--            montant total     = 28,32 $ (carte) contre 23,70 $ (espèces).
-- Écart total de 4,62 $ = 4,14 $ de pourboire (~90 %) + ~0,50 $ de suppléments.
-- Conclusion : les clients font les mêmes courses ; « la carte rapporte plus »
-- est FAUX. L'écart vient d'un biais d'enregistrement du pourboire.


-- ---------------------------------------------------------------------
-- ÉTAPE 3 : les trajets « gratuits » et « en litige » sont-ils de vraies courses ?
-- Observation : des trajets « No charge » (gratuits) ont un montant positif.
-- Hypothèse : ce sont de vraies courses, dont le taximètre a calculé le prix,
-- mais que le client n'a pas payées (ou conteste, pour les litiges).
-- Test : si c'est vrai, leurs distances et prix doivent ressembler à ceux des
-- courses payées. On utilise la MÉDIANE (résiste aux valeurs extrêmes) et le
-- PRIX PAR MILE : le tarif des taxis est réglementé, il doit être proche
-- d'un mode de paiement à l'autre.
-- ---------------------------------------------------------------------
SELECT
    p.payment_type_label,
    COUNT(*)                                     AS nb_trajets,
    ROUND(MEDIAN(f.trip_distance_miles), 2)      AS distance_mediane,
    ROUND(MEDIAN(f.fare_amount), 2)              AS prix_course_median,
    ROUND(AVG(f.fare_amount), 2)                 AS prix_course_moyen,
    ROUND(MEDIAN(f.fare_amount / NULLIF(f.trip_distance_miles, 0)), 2) AS prix_par_mile_median
FROM NYC_TAXI.MARTS.FCT_TRIPS f
JOIN NYC_TAXI.MARTS.DIM_PAYMENT_TYPE p
  ON p.payment_type_key = f.payment_type_key
WHERE f.total_amount <= 500                      -- sans les montants impossibles
GROUP BY 1
ORDER BY nb_trajets DESC;
-- Résultat : distances médianes de 1,26 à 1,68 mile, prix par mile de 7,22 à 8,12 $
-- pour tous les modes. Le prix par mile un peu plus élevé des trajets gratuits
-- vient de leur distance plus courte (la prise en charge, fixe, pèse plus).
-- Les trajets « No charge » (37 975) et « Dispute » (115 460) sont donc de vraies
-- courses, mais NON ENCAISSÉES ou CONTESTÉES : leur montant n'a pas été perçu.
-- Avec le filtre à 500 $, le prix de course moyen reste 18,13 $ (carte)
-- contre 18,05 $ (espèces) : la conclusion de l'étape 2 tient.
-- Flex Fare : courses plus longues (2,35 miles) et plus chères (17,08 $ médian),
-- cohérent avec un tarif fixé à l'avance (aéroports, longs trajets).


-- =====================================================================
-- CONCLUSIONS
-- 1. Les clients font les mêmes courses quel que soit le mode de paiement.
-- 2. L'écart apparent carte / espèces vient d'un biais d'enregistrement :
--    le pourboire en espèces existe, mais il est invisible dans les données.
-- 3. « La carte rapporte plus » est une conclusion FAUSSE.
-- 4. Pour l'entreprise, le pourboire revient au chauffeur et les taxes sont
--    reversées : l'indicateur pertinent est le prix de la course (fare_amount).
-- 5. Les courses gratuites et en litige ne rapportent rien (ou pas encore) :
--    la requête finale les exclut.
-- =====================================================================