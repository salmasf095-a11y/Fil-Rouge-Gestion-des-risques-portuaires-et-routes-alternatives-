-- ─────────────────────────────────────────────────────────────
-- KPI 1 : Score LPI Maroc vs Monde
-- ─────────────────────────────────────────────────────────────
SELECT
    iso3,
    lpi_score,
    rank,
    lpi_category,
    resilience_score,
    ROUND(lpi_score - (SELECT AVG(lpi_score) FROM fact_lpi), 2) AS ecart_moyenne_mondiale
FROM fact_lpi
WHERE iso3 IN ('MAR', 'EGY', 'TUN', 'DZA')
ORDER BY lpi_score DESC;
 
-- ─────────────────────────────────────────────────────────────
-- KPI 2 : Top 10 pays les plus performants
-- ─────────────────────────────────────────────────────────────
SELECT
    p.country_name,
    l.rank,
    l.lpi_score,
    l.resilience_score,
    l.lpi_category,
    l.infrastructure,
    l.timeliness
FROM fact_lpi l
JOIN dim_pays p ON l.iso3 = p.iso3
ORDER BY l.rank
LIMIT 10;
 
-- ─────────────────────────────────────────────────────────────
-- KPI 3 : Ports critiques — Score de risque élevé
-- ─────────────────────────────────────────────────────────────
SELECT
    port_name,
    country,
    harbor_size_label,
    max_depth,
    congestion_index,
    risk_score,
    risk_category,
    annual_teu_millions,
    statut_alerte
FROM v_ports_risque
WHERE risk_score > 0.5
ORDER BY risk_score DESC
LIMIT 15;
 
-- ─────────────────────────────────────────────────────────────
-- KPI 4 : Impact des crises sur le Canal de Suez
-- ─────────────────────────────────────────────────────────────
SELECT
    event_flag,
    nb_mois,
    avg_transits,
    min_transits,
    max_transits,
    avg_revenue_musd,
    impact_ratio,
    pct_perte_trafic
FROM v_suez_disruptions
ORDER BY pct_perte_trafic DESC;
 
-- ─────────────────────────────────────────────────────────────
-- KPI 5 : Évolution mensuelle du trafic Suez 2019-2024
-- ─────────────────────────────────────────────────────────────
SELECT
    date_val,
    year,
    month,
    total_transits,
    rolling_3m,
    rolling_12m,
    mom_change_pct,
    transit_vs_normal,
    event_flag,
    is_crisis
FROM fact_suez
ORDER BY date_val;
 
-- ─────────────────────────────────────────────────────────────
-- KPI 6 : Top 10 flux commerciaux 2023
-- ─────────────────────────────────────────────────────────────
SELECT
    reporter,
    partner,
    flow,
    year,
    trade_value_billion,
    trade_intensity,
    dependency_ratio,
    rang_partenaire
FROM v_top_partenaires
WHERE year = 2023
  AND flow = 'Export'
  AND rang_partenaire <= 3
ORDER BY reporter, rang_partenaire;
 
-- ─────────────────────────────────────────────────────────────
-- KPI 7 : Dépendance commerciale par pays (2023)
-- ─────────────────────────────────────────────────────────────
SELECT
    reporter,
    reporter_iso,
    ROUND(AVG(dependency_ratio), 3)         AS dep_ratio_moyen,
    ROUND(SUM(trade_value_billion), 1)      AS total_trade_Mrd_usd,
    COUNT(DISTINCT partner)                 AS nb_partenaires,
    MAX(trade_value_billion)                AS flux_max_Mrd
FROM fact_trade
WHERE year = 2023
GROUP BY reporter, reporter_iso
ORDER BY dep_ratio_moyen DESC
LIMIT 15;
 
-- ─────────────────────────────────────────────────────────────
-- KPI 8 : Routes alternatives — coût et empreinte CO2
-- ─────────────────────────────────────────────────────────────
SELECT
    start_port,
    destination_city,
    country_name,
    distance_km,
    duration_hours,
    cost_estimate_usd,
    co2_kg,
    risk_level,
    corridor,
    alternative_available,
    pays_lpi
FROM v_routes_alternatives
ORDER BY risk_level DESC, distance_km;
 
-- ─────────────────────────────────────────────────────────────
-- KPI 9 : Score de risque composite port + LPI pays
-- ─────────────────────────────────────────────────────────────
SELECT
    port_name,
    country,
    iso3,
    risk_score          AS port_risk,
    congestion_index,
    lpi_score           AS pays_lpi,
    resilience_score,
    statut_alerte,
    ROUND(
        risk_score * 0.6 + (1 - COALESCE(lpi_score, 3) / 5.0) * 0.4
    , 3)                AS score_vulnerabilite_global
FROM v_ports_risque
ORDER BY score_vulnerabilite_global DESC
LIMIT 20;
 
-- ─────────────────────────────────────────────────────────────
-- KPI 10 : Vue synthèse globale (dashboard)
-- ─────────────────────────────────────────────────────────────
SELECT * FROM v_kpi_global;
 
-- ─────────────────────────────────────────────────────────────
-- ANALYSE : Corrélation LPI score vs congestion portuaire
-- ─────────────────────────────────────────────────────────────
SELECT
    p.country_name,
    p.iso3,
    l.lpi_score,
    l.resilience_score,
    ROUND(AVG(po.congestion_index), 3)  AS avg_congestion,
    ROUND(AVG(po.risk_score), 3)        AS avg_risk_score,
    COUNT(po.port_id)                   AS nb_ports
FROM dim_pays p
JOIN fact_lpi   l  ON p.iso3 = l.iso3
JOIN dim_port   po ON p.iso3 = po.iso3
GROUP BY p.country_name, p.iso3, l.lpi_score, l.resilience_score
ORDER BY l.lpi_score DESC;
 
-- ─────────────────────────────────────────────────────────────
-- ANALYSE : Simulation blocage Suez — impact commercial
-- ─────────────────────────────────────────────────────────────
WITH suez_normal AS (
    SELECT AVG(total_transits) AS avg_normal
    FROM fact_suez WHERE is_crisis = 0
),
suez_crise AS (
    SELECT AVG(total_transits) AS avg_crise
    FROM fact_suez WHERE is_crisis = 1
)
SELECT
    ROUND(avg_normal, 0)                                AS transits_normaux_mois,
    ROUND(avg_crise, 0)                                 AS transits_crise_mois,
    ROUND((1 - avg_crise / avg_normal) * 100, 1)        AS pct_reduction_trafic,
    ROUND(avg_normal - avg_crise, 0)                    AS transits_perdus_mois,
    ROUND((avg_normal - avg_crise) * 12, 0)             AS transits_perdus_annee_estimee
FROM suez_normal, suez_crise;