# Réponse à la direction d'Hudson Cab Partners

## La question

Où et quand la demande de taxis jaunes est-elle la plus forte à New York, et combien rapporte un trajet selon la zone, l'heure et le mode de paiement ?

## La requête

Fichier : `snowflake/requete_finale.sql`. Elle part de la table de faits `MARTS.FCT_TRIPS` (trajets valides uniquement), écarte les montants impossibles (plus de 500 $) et les courses non encaissées (gratuites ou en litige), regroupe par zone et heure de prise en charge, et calcule la demande, le prix de la course et le montant payé par trajet, au total et selon le mode de paiement.

```sql
SELECT
    z.zone_name                                              AS zone,
    z.borough                                                AS arrondissement,
    f.pickup_hour                                            AS heure,
    COUNT(*)                                                 AS nb_trajets,
    ROUND(COUNT(*) / COUNT(DISTINCT f.pickup_date), 0)       AS trajets_par_jour,
    ROUND(AVG(f.fare_amount), 2)                             AS prix_course_moyen,
    ROUND(MEDIAN(f.fare_amount), 2)                          AS prix_course_median,
    ROUND(AVG(f.total_amount), 2)                            AS montant_moyen,
    ROUND(100 * COUNT_IF(f.payment_type_key = 1) / COUNT(*), 1)        AS part_carte_pct,
    ROUND(AVG(IFF(f.payment_type_key = 1, f.total_amount, NULL)), 2)   AS montant_moyen_carte,
    ROUND(AVG(IFF(f.payment_type_key = 2, f.total_amount, NULL)), 2)   AS montant_moyen_especes
FROM NYC_TAXI.MARTS.FCT_TRIPS f
JOIN NYC_TAXI.MARTS.DIM_ZONE z
  ON z.zone_key = f.pickup_zone_key
WHERE NOT z.is_unknown_zone
  AND f.total_amount <= 500
  AND f.payment_type_key NOT IN (3, 4)
GROUP BY z.zone_name, z.borough, f.pickup_hour
ORDER BY nb_trajets DESC
LIMIT 10;
```

## Le résultat : les 10 premières lignes

Trajets valides de janvier à mars 2025 (90 jours), hors montants impossibles (plus de 500 $) et hors courses non encaissées. Heure de prise en charge, heure locale de New York. Montants en dollars. Le **prix de la course** exclut le pourboire et les taxes ; le **montant moyen** est ce que paie le client.

| Zone | Arrondissement | Heure | Trajets (3 mois) | Trajets par jour | Prix de la course (moyen) | Prix de la course (médian) | Montant moyen payé | Part carte | Moyenne carte | Moyenne espèces |
|---|---|---|---|---|---|---|---|---|---|---|
| Midtown Center | Manhattan | 18 h | 45 978 | 511 | 14,46 | 12,80 | 24,40 | 83,2 % | 25,06 | 19,93 |
| Midtown Center | Manhattan | 17 h | 45 062 | 501 | 15,40 | 13,45 | 25,63 | 84,4 % | 26,35 | 20,74 |
| Midtown Center | Manhattan | 19 h | 38 770 | 431 | 13,91 | 12,10 | 23,62 | 81,7 % | 24,25 | 19,36 |
| Midtown Center | Manhattan | 20 h | 38 518 | 428 | 14,33 | 12,37 | 22,67 | 72,3 % | 23,61 | 18,61 |
| Midtown Center | Manhattan | 16 h | 36 702 | 408 | 15,58 | 12,80 | 25,77 | 83,6 % | 26,53 | 21,27 |
| Upper East Side North | Manhattan | 15 h | 36 598 | 407 | 13,46 | 11,40 | 20,37 | 81,3 % | 20,64 | 17,12 |
| Upper East Side South | Manhattan | 14 h | 36 482 | 405 | 12,90 | 10,70 | 19,98 | 81,8 % | 20,41 | 16,85 |
| Upper East Side South | Manhattan | 15 h | 36 399 | 404 | 12,90 | 10,70 | 19,98 | 82,4 % | 20,34 | 16,94 |
| Times Sq/Theatre District | Manhattan | 21 h | 36 340 | 404 | 15,15 | 12,80 | 23,58 | 71,2 % | 24,50 | 18,94 |
| Upper East Side South | Manhattan | 18 h | 36 093 | 401 | 12,30 | 10,00 | 21,23 | 81,9 % | 21,54 | 17,97 |

## Ce qu'il faut en retenir

1. **La demande se concentre à Midtown Center en fin de journée** : entre 16 h et 20 h, ce seul quartier occupe la moitié du top 10, avec un pic d'environ 500 trajets par jour à 17 h et 18 h. C'est là et à ce moment que la flotte doit être la plus présente. L'Upper East Side génère aussi une forte demande l'après-midi (14 h-15 h), et Times Square prend le relais vers 21 h, à la sortie des théâtres.
2. **Une course à Midtown rapporte un peu plus qu'à l'Upper East Side** : 13,90 à 15,60 $ de prix de course en moyenne, contre 12,30 à 13,50 $. L'écart est plus marqué sur le montant payé par le client (22,70 à 25,90 $ contre 20 à 21,30 $), mais cette différence supplémentaire est faite de pourboires et de surcharges qui ne reviennent pas à la flotte. Plus largement, le prix de la course ne représente qu'environ 60 % de ce que paie le client.
3. **Plus de 8 trajets sur 10 sont payés par carte, mais le mode de paiement ne change pas ce que rapporte la course.** Le prix moyen de la course est le même par carte (18,13 $) et en espèces (18,05 $). L'écart de 4 à 6 $ sur le montant total vient presque entièrement du pourboire (4,14 $ en moyenne par carte), qui n'est enregistré que pour les paiements par carte. On ne peut donc pas conclure que les clients qui paient par carte rapportent davantage.

## Les limites

- **Période courte** : trois mois d'hiver (janvier à mars 2025). La saisonnalité (été, fêtes) n'est pas visible.
- **Trajets écartés** : 815 648 trajets (7,3 %) ont été exclus par les règles de qualité (distance nulle, montant négatif, durée impossible, date hors du mois…). Le détail par motif est dans `MARTS.MART_DATA_QUALITY`.
- **Zones inconnues** : les zones 264 et 265 du référentiel TLC sont exclues, car elles ne correspondent à aucun lieu réel.
- **Valeurs aberrantes** : des montants impossibles ont passé les règles de nettoyage, qui rejettent les montants négatifs mais ne plafonnent pas les montants. Le plus extrême : un trajet du 21 février 2025 à 132 555 $ pour 2,2 miles, qui faisait passer à lui seul la moyenne de Midtown Center à 17 h de 25,63 $ à 28,57 $. La requête écarte donc les trajets de plus de 500 $ : 87 trajets sur 10,4 millions (0,001 %), un seuil mesuré qui n'écarte que l'impossible. C'est une correction locale : la bonne solution est d'ajouter cette règle en amont, dans `int_trips__flagged.sql` (rejet au-delà d'un montant maximal, ou d'un prix par mile incohérent), pour que tout le pipeline en profite. La médiane du prix de la course, peu sensible aux valeurs extrêmes, est affichée à côté de la moyenne. Enquête complète : `snowflake/enquete_valeur_aberrante.sql`.
- **Courses non encaissées exclues** : 37 975 trajets gratuits (No charge) et 115 460 trajets en litige (Dispute) sont de vraies courses, aux distances et aux prix comparables aux autres, mais leur montant n'a pas été encaissé ou est contesté. Ils sont exclus de la requête, qui mesure ce que rapporte un trajet ; ils restent comptés dans `FCT_TRIPS`. Enquête complète : `snowflake/enquete_mode_paiement.sql`.
- **Pourboires en espèces non enregistrés** : sur 1 063 448 trajets payés en espèces, aucun pourboire n'est enregistré (contre 94 % des trajets par carte, 4,14 $ en moyenne). Toute comparaison de revenus entre carte et espèces est donc biaisée en faveur de la carte.
- **Ce qui revient réellement à l'entreprise** : le montant total payé par le client inclut le pourboire, qui revient au chauffeur, et des taxes et surcharges reversées aux autorités (taxe MTA, surcharges de congestion, péage urbain). Pour la flotte, l'indicateur pertinent est plutôt le prix de la course. Ce que l'entreprise en perçoit dépend de son modèle économique (exploitation directe ou location des taxis aux chauffeurs), qui n'apparaît pas dans les données et reste à préciser avec la direction.
- **Demande servie, pas demande totale** : on ne voit que les trajets effectués en taxi jaune, ni les clients qui n'ont pas trouvé de taxi, ni ceux partis en VTC.
- **Zone de prise en charge uniquement** : la destination n'est pas analysée.