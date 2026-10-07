-- Les trajets valides du mois existent et ne contiennent aucun doublon.
-- Placé avant les marts : un doublon fausserait tous les comptages de la direction.
SELECT
    COUNT(*) > 0                          AS mois_non_vide,
    COUNT(*) = COUNT(DISTINCT trip_sk)    AS aucun_doublon
FROM NYC_TAXI.INTERMEDIATE.INT_TRIPS__ENRICHED
WHERE source_file_month = '{{ ds }}'::date;