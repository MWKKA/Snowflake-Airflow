-- =====================================================================
-- enquete_valeur_aberrante.sql
-- Enquête sur un chiffre surprenant de la requête finale.
--
-- POINT DE DÉPART (l'observation)
-- Dans le top 10, Midtown Center à 17 h affiche :
--   montant moyen global   = 28,57 $
--   montant moyen carte    = 26,35 $
--   montant moyen espèces  = 20,74 $
-- La moyenne GLOBALE est plus élevée que celle de CHACUN des deux modes
-- principaux. Une moyenne globale est un mélange des moyennes de chaque
-- groupe : elle ne peut pas dépasser toutes les moyennes qui la composent...
-- sauf si un AUTRE groupe, absent de nos colonnes, a des montants bien plus
-- élevés. Réflexe : un chiffre « impossible » se vérifie avant d'être présenté.
--
-- MÉTHODE : observer -> hypothèse -> tester -> conclure (ou reformuler)
-- =====================================================================

USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;


-- ---------------------------------------------------------------------
-- ÉTAPE 1 : décomposer la moyenne par groupe
-- Hypothèse : un mode de paiement que la requête finale n'affiche pas
-- (Flex Fare, litige, gratuit...) tire la moyenne vers le haut.
-- Test : on refait le calcul pour CE couple zone × heure seulement,
-- mais ventilé par TOUS les modes de paiement.
-- Ce qu'on cherche : un groupe dont la moyenne sort nettement du lot.
-- ---------------------------------------------------------------------
SELECT
    p.payment_type_label,                          -- libellé lisible plutôt que le code
    COUNT(*)                        AS nb,          -- combien de trajets dans chaque groupe
    ROUND(AVG(f.total_amount), 2)   AS montant_moyen
FROM NYC_TAXI.MARTS.FCT_TRIPS f
JOIN NYC_TAXI.MARTS.DIM_ZONE z
  ON z.zone_key = f.pickup_zone_key                -- pour filtrer par NOM de zone
JOIN NYC_TAXI.MARTS.DIM_PAYMENT_TYPE p
  ON p.payment_type_key = f.payment_type_key       -- pour afficher le NOM du mode de paiement
WHERE z.zone_name = 'Midtown Center'               -- on isole exactement la ligne suspecte
  AND f.pickup_hour = 17
GROUP BY 1
ORDER BY nb DESC;
-- Résultat : « No charge » (course gratuite) = 142 trajets à 951,63 $ de moyenne.
-- Une course GRATUITE à près de 1 000 $ : suspect. Le groupe en cause est trouvé...
-- mais attention à ne pas conclure trop vite (voir étape 2).


-- ---------------------------------------------------------------------
-- ÉTAPE 2 : mesurer l'ampleur du phénomène
-- Question : est-ce un problème RÉPANDU (beaucoup de trajets chers)
-- ou PONCTUEL (quelques valeurs extrêmes) ?
-- Test : combien de trajets valides dépassent un montant manifestement
-- anormal pour un taxi (500 $), sur TOUT le trimestre ?
-- La sous-requête (SELECT COUNT(*) ...) donne le total, pour exprimer
-- le résultat en pourcentage : un chiffre brut seul ne dit pas si c'est beaucoup.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*) AS trajets_plus_de_500,
    ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM NYC_TAXI.MARTS.FCT_TRIPS), 3) AS part_pct
FROM NYC_TAXI.MARTS.FCT_TRIPS
WHERE total_amount > 500;
-- Résultat : 87 trajets sur 10,4 millions (0,001 %).
-- Contradiction avec l'étape 1 : si les 142 trajets « No charge » valaient tous
-- ~950 $, il y en aurait au moins 142 au-dessus de 500 $. Donc l'hypothèse
-- « 142 trajets aberrants » est FAUSSE. Nouvelle hypothèse : une moyenne
-- élevée peut venir d'UNE seule valeur énorme. On reformule et on reteste.


-- ---------------------------------------------------------------------
-- ÉTAPE 3 : regarder les lignes elles-mêmes
-- Hypothèse reformulée : un ou deux trajets extrêmes faussent la moyenne
-- des 142 trajets « No charge ».
-- Test : afficher les trajets de ce groupe, du plus cher au moins cher.
-- Quand une moyenne intrigue, on finit toujours par regarder les LIGNES :
-- un agrégat cache les détails, les lignes les montrent.
-- On affiche aussi la distance et le prix de la course pour juger
-- la cohérence (un prix doit être en rapport avec la distance).
-- ---------------------------------------------------------------------
SELECT
    f.pickup_at,
    f.trip_distance_miles,
    f.fare_amount,                                 -- prix calculé par le compteur
    f.total_amount                                 -- prix total payé
FROM NYC_TAXI.MARTS.FCT_TRIPS f
JOIN NYC_TAXI.MARTS.DIM_ZONE z
  ON z.zone_key = f.pickup_zone_key
WHERE z.zone_name = 'Midtown Center'
  AND f.pickup_hour = 17
  AND f.payment_type_key = 3                       -- 3 = No charge (vérifié dans DIM_PAYMENT_TYPE)
ORDER BY f.total_amount DESC                       -- les plus gros montants en premier
LIMIT 5;                                           -- 5 lignes suffisent pour voir s'il y a un écart
-- Résultat : UN trajet du 21/02/2025 à 132 555 $ pour 2,2 miles,
-- puis des montants normaux (118 $, 53 $, 52 $...).
-- Conclusion : une seule erreur de saisie fausse toute la moyenne.


-- ---------------------------------------------------------------------
-- ÉTAPE 4 : mesurer l'impact et trouver un indicateur plus fiable
-- Question : quelle serait la « vraie » moyenne sans cette valeur,
-- et existe-t-il une mesure qui résiste à ce genre d'erreur ?
-- Test 1 : moyenne en excluant le trajet aberrant (filtre volontairement
--          large, < 100 000 $, pour n'écarter QUE lui).
-- Test 2 : la médiane, la valeur du milieu quand on trie les montants.
--          Une valeur extrême ne la déplace presque pas, contrairement
--          à la moyenne, qui additionne tout.
-- ---------------------------------------------------------------------
SELECT
    ROUND(AVG(f.total_amount), 2)    AS montant_moyen_sans_aberrant,
    ROUND(MEDIAN(f.total_amount), 2) AS montant_median
FROM NYC_TAXI.MARTS.FCT_TRIPS f
JOIN NYC_TAXI.MARTS.DIM_ZONE z
  ON z.zone_key = f.pickup_zone_key
WHERE z.zone_name = 'Midtown Center'
  AND f.pickup_hour = 17
  AND f.total_amount < 100000;                     -- exclut uniquement le trajet à 132 555 $
-- Résultat : moyenne 25,63 $ (au lieu de 28,57 $), médiane 23,06 $.
-- Sans l'erreur, 17 h ressemble aux heures voisines (16 h : 25,77 $ ; 18 h : 24,40 $) :
-- le « pic » de 17 h n'existait pas.
-- Médiane < moyenne : la plupart des courses sont courtes et peu chères,
-- quelques longues courses tirent la moyenne vers le haut. Normal pour des prix.


-- =====================================================================
-- CONCLUSIONS
-- 1. Un seul trajet sur 10,4 millions suffisait à créer un faux « pic ».
-- 2. Les règles de nettoyage rejettent les montants négatifs mais ne
--    plafonnent pas les montants. Décision : la requête finale écarte les
--    trajets de plus de 500 $ (seuil mesuré : 0,001 % des trajets).
--    Une règle à ajouter en amont, dans int_trips__flagged, est à proposer.
-- 3. Pour décrire un trajet « typique », la médiane est plus fiable
--    que la moyenne : la requête finale affiche les deux.
-- =====================================================================