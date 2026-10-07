-- La part de trajets écartés par les règles de nettoyage reste sous le seuil.
-- Un taux anormal signale un fichier corrompu ou un changement de format à la source.
SELECT
    COUNT_IF(rejection_reason IS NOT NULL) / NULLIF(COUNT(*), 0)
        < {{ params.max_rejection_rate }}  AS taux_rejet_acceptable
FROM NYC_TAXI.INTERMEDIATE.INT_TRIPS__FLAGGED
WHERE source_file_month = '{{ ds }}'::date;