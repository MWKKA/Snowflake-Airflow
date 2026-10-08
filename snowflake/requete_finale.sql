-- =====================================================================
-- requete_finale.sql
-- Question de la direction : où et quand la demande de taxis jaunes est-elle
-- la plus forte, et combien rapporte un trajet selon la zone, l'heure et le
-- mode de paiement ?
-- Périmètre : trajets valides de janvier à mars 2025 (MARTS.FCT_TRIPS),
-- hors montants impossibles et hors courses non encaissées.
-- =====================================================================
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

SELECT
    -- OÙ et QUAND : la zone (nom lisible via la dimension) et l'heure de prise en charge
    z.zone_name                                              AS zone,
    z.borough                                                AS arrondissement,
    f.pickup_hour                                            AS heure,

    -- LA DEMANDE : sur 3 mois, puis ramenée à une journée moyenne (plus parlant)
    COUNT(*)                                                 AS nb_trajets,
    ROUND(COUNT(*) / COUNT(DISTINCT f.pickup_date), 0)       AS trajets_par_jour,

    -- CE QUE RAPPORTE UN TRAJET
    -- prix de la course seul : ni taxes reversées, ni pourboire (qui revient au chauffeur)
    ROUND(AVG(f.fare_amount), 2)                             AS prix_course_moyen,
    -- la médiane résiste aux valeurs extrêmes, contrairement à la moyenne
    ROUND(MEDIAN(f.fare_amount), 2)                          AS prix_course_median,
    -- montant total payé par le client : course + suppléments + taxes + péages + pourboire carte
    ROUND(AVG(f.total_amount), 2)                            AS montant_moyen,

    -- LE MODE DE PAIEMENT (codes vérifiés dans DIM_PAYMENT_TYPE : 1 = carte, 2 = espèces)
    ROUND(100 * COUNT_IF(f.payment_type_key = 1) / COUNT(*), 1)        AS part_carte_pct,
    -- IFF garde le montant du mode voulu, NULL sinon ; AVG ignore les NULL
    ROUND(AVG(IFF(f.payment_type_key = 1, f.total_amount, NULL)), 2)   AS montant_moyen_carte,
    ROUND(AVG(IFF(f.payment_type_key = 2, f.total_amount, NULL)), 2)   AS montant_moyen_especes
FROM NYC_TAXI.MARTS.FCT_TRIPS f
JOIN NYC_TAXI.MARTS.DIM_ZONE z
  ON z.zone_key = f.pickup_zone_key
WHERE NOT z.is_unknown_zone              -- zones 264 et 265 : « inconnue », pas un lieu réel
  AND f.total_amount <= 500              -- montants impossibles : 87 trajets (0,001 %), dont un à
                                         -- 132 555 $ pour 2,2 miles (enquete_valeur_aberrante.sql).
                                         -- Correction locale : la règle devrait être ajoutée en
                                         -- amont, dans int_trips__flagged.
  AND f.payment_type_key NOT IN (3, 4)   -- 3 = No charge, 4 = Dispute : vraies courses mais non
                                         -- encaissées (enquete_mode_paiement.sql, étape 3)
GROUP BY z.zone_name, z.borough, f.pickup_hour
ORDER BY nb_trajets DESC                 -- la demande décide du classement
LIMIT 10;