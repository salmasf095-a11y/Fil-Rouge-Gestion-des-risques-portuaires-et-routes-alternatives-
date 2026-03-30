--  Architecture : Schéma en étoile
--  Tables de dimension : dim_pays, dim_port, dim_temps
--  Tables de faits     : fact_lpi, fact_trade, fact_suez, fact_routes
-- =============================================================

-- Création de la base (à exécuter en superuser si besoin)
-- CREATE DATABASE portuaire_db;
-- \c portuaire_db

-- Suppression des tables si elles existent (pour re-exécution propre)
DROP TABLE IF EXISTS fact_routes   CASCADE;
DROP TABLE IF EXISTS fact_suez     CASCADE;
DROP TABLE IF EXISTS fact_trade    CASCADE;
DROP TABLE IF EXISTS fact_lpi      CASCADE;
DROP TABLE IF EXISTS dim_port      CASCADE;
DROP TABLE IF EXISTS dim_pays      CASCADE;
DROP TABLE IF EXISTS dim_temps     CASCADE;

-- =============================================================
-- DIMENSION 1 : dim_pays
-- =============================================================
CREATE TABLE dim_pays (
pays_id         SERIAL          PRIMARY KEY,
iso3            CHAR(3)         NOT NULL UNIQUE,
country_name    VARCHAR(100)    NOT NULL,
region          VARCHAR(50),
created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  dim_pays          IS 'Référentiel des pays — clé de jointure entre LPI et Trade';
COMMENT ON COLUMN dim_pays.iso3     IS 'Code ISO 3166-1 alpha-3 (ex: MAR, EGY, FRA)';

-- =============================================================
-- DIMENSION 2 : dim_port
-- =============================================================
CREATE TABLE dim_port (
port_id             VARCHAR(10)     PRIMARY KEY,
port_name           VARCHAR(150)    NOT NULL,
country             VARCHAR(100)    NOT NULL,
iso3                CHAR(3)         REFERENCES dim_pays(iso3),
latitude            DECIMAL(9,6)    NOT NULL,
longitude           DECIMAL(9,6)    NOT NULL,
harbor_size         CHAR(2),
harbor_size_label   VARCHAR(20),
facility_size       VARCHAR(20),
max_depth           DECIMAL(5,2),
nearest_city        VARCHAR(100),
anchorage           SMALLINT        DEFAULT 0 CHECK (anchorage IN (0,1)),
drydock             SMALLINT        DEFAULT 0 CHECK (drydock   IN (0,1)),
railway             SMALLINT        DEFAULT 0 CHECK (railway   IN (0,1)),
tide                DECIMAL(4,1),
congestion_index    DECIMAL(4,3)    CHECK (congestion_index BETWEEN 0 AND 1),
annual_teu_millions DECIMAL(6,1),
risk_score          DECIMAL(5,3)    CHECK (risk_score BETWEEN 0 AND 1),
risk_category       VARCHAR(20),
infrastructure_score DECIMAL(5,3)  CHECK (infrastructure_score BETWEEN 0 AND 1),
created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  dim_port                  IS 'World Port Index — infrastructure et risque des ports mondiaux';
COMMENT ON COLUMN dim_port.risk_score       IS 'Score composite : (1-depth/max)*0.4 + congestion*0.6';
COMMENT ON COLUMN dim_port.congestion_index IS '0 = aucune congestion, 1 = congestion maximale';

-- =============================================================
-- DIMENSION 3 : dim_temps
-- =============================================================
CREATE TABLE dim_temps (
temps_id        SERIAL      PRIMARY KEY,
date_val        DATE        NOT NULL UNIQUE,
year            SMALLINT    NOT NULL,
month           SMALLINT    NOT NULL CHECK (month BETWEEN 1 AND 12),
quarter         SMALLINT    NOT NULL CHECK (quarter BETWEEN 1 AND 4),
quarter_label   CHAR(2),
year_month      VARCHAR(8),
semester        SMALLINT    GENERATED ALWAYS AS (CASE WHEN month <= 6 THEN 1 ELSE 2 END) STORED
);

COMMENT ON TABLE dim_temps IS 'Dimension temporelle pour les séries Suez 2019–2024';

-- =============================================================
-- FAIT 1 : fact_lpi
-- Performance logistique par pays (World Bank LPI)
-- =============================================================
CREATE TABLE fact_lpi (
lpi_id                  SERIAL          PRIMARY KEY,
iso3                    CHAR(3)         NOT NULL REFERENCES dim_pays(iso3),
year                    SMALLINT        NOT NULL DEFAULT 2023,
rank                    SMALLINT        NOT NULL,
lpi_score               DECIMAL(4,2)    NOT NULL CHECK (lpi_score BETWEEN 1 AND 5),
customs                 DECIMAL(4,2)    CHECK (customs BETWEEN 1 AND 5),
infrastructure          DECIMAL(4,2)    CHECK (infrastructure BETWEEN 1 AND 5),
international_shipments DECIMAL(4,2)    CHECK (international_shipments BETWEEN 1 AND 5),
logistics_quality       DECIMAL(4,2)    CHECK (logistics_quality BETWEEN 1 AND 5),
tracking_tracing        DECIMAL(4,2)    CHECK (tracking_tracing BETWEEN 1 AND 5),
timeliness              DECIMAL(4,2)    CHECK (timeliness BETWEEN 1 AND 5),
lpi_category            VARCHAR(20),
resilience_score        DECIMAL(5,3),
above_world_avg         SMALLINT        CHECK (above_world_avg IN (0,1)),
created_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
UNIQUE (iso3, year)
);

COMMENT ON TABLE  fact_lpi              IS 'Scores LPI 2023 — World Bank Logistics Performance Index';
COMMENT ON COLUMN fact_lpi.resilience_score IS 'Score pondéré : infra*0.3 + quality*0.25 + timeliness*0.25 + customs*0.2';

-- =============================================================
-- FAIT 2 : fact_trade
-- Flux commerciaux internationaux (UN Comtrade 2021–2024)
-- =============================================================
CREATE TABLE fact_trade (
trade_id            SERIAL          PRIMARY KEY,
year                SMALLINT        NOT NULL,
reporter            VARCHAR(100)    NOT NULL,
reporter_iso        CHAR(3)         REFERENCES dim_pays(iso3),
partner             VARCHAR(100)    NOT NULL,
partner_iso         CHAR(3)         REFERENCES dim_pays(iso3),
flow                VARCHAR(10)     NOT NULL CHECK (flow IN ('Export','Import')),
trade_value_usd     BIGINT          NOT NULL CHECK (trade_value_usd > 0),
commodity           VARCHAR(20)     DEFAULT 'TOTAL',
trade_value_billion DECIMAL(10,3),
trade_intensity     VARCHAR(15),
trade_balance       BIGINT,
dependency_ratio    DECIMAL(5,3)    CHECK (dependency_ratio BETWEEN 0 AND 1),
created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
UNIQUE (year, reporter_iso, partner_iso, flow)
);

COMMENT ON TABLE  fact_trade                IS 'Flux commerciaux import/export 2021–2024 — UN Comtrade';
COMMENT ON COLUMN fact_trade.dependency_ratio IS 'import / (export + import) : 0=équilibré, 1=dépendant';

-- =============================================================
-- FAIT 3 : fact_suez
-- Trafic mensuel Canal de Suez 2019–2024
-- =============================================================
CREATE TABLE fact_suez (
suez_id             SERIAL          PRIMARY KEY,
temps_id            INTEGER         REFERENCES dim_temps(temps_id),
date_val            DATE            NOT NULL UNIQUE,
year                SMALLINT        NOT NULL,
month               SMALLINT        NOT NULL,
northbound          INTEGER         NOT NULL CHECK (northbound >= 0),
southbound          INTEGER         NOT NULL CHECK (southbound >= 0),
total_transits      INTEGER         NOT NULL CHECK (total_transits >= 0),
net_tonnage_million DECIMAL(6,1),
revenue_million_usd DECIMAL(8,1),
event_flag          VARCHAR(50)     DEFAULT 'Normal',
quarter             SMALLINT,
quarter_label       CHAR(2),
year_month          VARCHAR(8),
mom_change_pct      DECIMAL(7,4),
rolling_3m          DECIMAL(7,1),
rolling_12m         DECIMAL(7,1),
is_crisis           SMALLINT        CHECK (is_crisis IN (0,1)),
transit_vs_normal   DECIMAL(6,3),
created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  fact_suez             IS 'Trafic mensuel Canal de Suez 2019–2024 — disruptions identifiées';
COMMENT ON COLUMN fact_suez.is_crisis   IS '1 = période de crise (Ever Given, Houthi, COVID)';
COMMENT ON COLUMN fact_suez.transit_vs_normal IS 'Ratio transits / moyenne normale (1.0 = normal)';

-- =============================================================
-- FAIT 4 : fact_routes
-- Routes routières port → ville (API OSRM)
-- =============================================================
CREATE TABLE fact_routes (
route_id            SERIAL          PRIMARY KEY,
port_id             VARCHAR(10)     REFERENCES dim_port(port_id),
start_port          VARCHAR(150)    NOT NULL,
destination_city    VARCHAR(100)    NOT NULL,
country_iso         CHAR(3)         REFERENCES dim_pays(iso3),
port_lat            DECIMAL(9,6),
port_lon            DECIMAL(9,6),
city_lat            DECIMAL(9,6),
city_lon            DECIMAL(9,6),
distance_km         DECIMAL(8,1)    NOT NULL CHECK (distance_km > 0),
duration_minutes    INTEGER         NOT NULL CHECK (duration_minutes > 0),
duration_hours      DECIMAL(6,2),
route_type          VARCHAR(20),
alternative_available VARCHAR(5)   CHECK (alternative_available IN ('Yes','No')),
risk_level          VARCHAR(10)     CHECK (risk_level IN ('Low','Medium','High')),
speed_kmh           DECIMAL(6,1),
cost_estimate_usd   DECIMAL(10,1),
co2_kg              DECIMAL(8,1),
corridor            VARCHAR(25),
source              VARCHAR(100)    DEFAULT 'OSRM API',
extracted_at        TIMESTAMP,
created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
UNIQUE (start_port, destination_city)
);

COMMENT ON TABLE  fact_routes               IS 'Routes routières port–ville — API OSRM';
COMMENT ON COLUMN fact_routes.cost_estimate_usd IS 'Estimation coût transport : distance × 2.1 USD/km';
COMMENT ON COLUMN fact_routes.co2_kg        IS 'Empreinte CO2 estimée : distance × 0.062 kg/km';

-- =============================================================
-- INDEX pour optimiser les requêtes analytiques
-- =============================================================
CREATE INDEX idx_lpi_iso3       ON fact_lpi   (iso3);
CREATE INDEX idx_lpi_score      ON fact_lpi   (lpi_score DESC);
CREATE INDEX idx_trade_year     ON fact_trade (year);
CREATE INDEX idx_trade_reporter ON fact_trade (reporter_iso);
CREATE INDEX idx_trade_partner  ON fact_trade (partner_iso);
CREATE INDEX idx_trade_flow     ON fact_trade (flow);
CREATE INDEX idx_suez_date      ON fact_suez  (date_val);
CREATE INDEX idx_suez_year      ON fact_suez  (year);
CREATE INDEX idx_suez_crisis    ON fact_suez  (is_crisis);
CREATE INDEX idx_port_iso3      ON dim_port   (iso3);
CREATE INDEX idx_port_risk      ON dim_port   (risk_score DESC);
CREATE INDEX idx_routes_port    ON fact_routes(start_port);
CREATE INDEX idx_routes_risk    ON fact_routes(risk_level);

-- =============================================================
-- VUES ANALYTIQUES
-- =============================================================

-- Vue 1 : Performance logistique complète par pays
CREATE OR REPLACE VIEW v_performance_pays AS
SELECT
p.country_name,
p.iso3,
p.region,
l.rank,
l.lpi_score,
l.resilience_score,
l.lpi_category,
l.customs,
l.infrastructure,
l.timeliness,
l.logistics_quality,
l.above_world_avg,
COUNT(DISTINCT po.port_id)          AS nb_ports,
AVG(po.risk_score)                  AS avg_port_risk,
AVG(po.congestion_index)            AS avg_congestion,
SUM(po.annual_teu_millions)         AS total_teu_millions
FROM dim_pays p
LEFT JOIN fact_lpi   l  ON p.iso3 = l.iso3
LEFT JOIN dim_port   po ON p.iso3 = po.iso3
GROUP BY p.country_name, p.iso3, p.region,
        l.rank, l.lpi_score, l.resilience_score, l.lpi_category,
        l.customs, l.infrastructure, l.timeliness, l.logistics_quality,
        l.above_world_avg;

-- Vue 2 : Analyse trafic Suez — disruptions
CREATE OR REPLACE VIEW v_suez_disruptions AS
SELECT
year,
event_flag,
COUNT(*)                            AS nb_mois,
ROUND(AVG(total_transits), 0)       AS avg_transits,
MIN(total_transits)                 AS min_transits,
MAX(total_transits)                 AS max_transits,
ROUND(AVG(revenue_million_usd), 1)  AS avg_revenue_musd,
ROUND(AVG(transit_vs_normal), 3)    AS impact_ratio,
ROUND((1 - AVG(transit_vs_normal)) * 100, 1) AS pct_perte_trafic
FROM fact_suez
GROUP BY year, event_flag
ORDER BY year, event_flag;

-- Vue 3 : Top partenaires commerciaux par pays
CREATE OR REPLACE VIEW v_top_partenaires AS
SELECT
reporter,
reporter_iso,
partner,
partner_iso,
flow,
year,
trade_value_billion,
trade_intensity,
dependency_ratio,
RANK() OVER (
    PARTITION BY reporter_iso, flow, year
    ORDER BY trade_value_usd DESC
) AS rang_partenaire
FROM fact_trade;

-- Vue 4 : Ports à risque élevé avec LPI du pays
CREATE OR REPLACE VIEW v_ports_risque AS
SELECT
po.port_id,
po.port_name,
po.country,
po.iso3,
po.harbor_size_label,
po.max_depth,
po.congestion_index,
po.risk_score,
po.risk_category,
po.infrastructure_score,
po.annual_teu_millions,
l.lpi_score,
l.lpi_category,
l.resilience_score,
CASE
    WHEN po.risk_score > 0.7 AND l.lpi_score < 3.0 THEN 'Critique'
    WHEN po.risk_score > 0.5 OR  l.lpi_score < 3.0 THEN 'Vigilance'
    ELSE 'Normal'
END AS statut_alerte
FROM dim_port po
LEFT JOIN fact_lpi l ON po.iso3 = l.iso3
ORDER BY po.risk_score DESC;

-- Vue 5 : Routes alternatives avec coût et CO2
CREATE OR REPLACE VIEW v_routes_alternatives AS
SELECT
r.start_port,
r.destination_city,
r.country_iso,
p.country_name,
r.distance_km,
r.duration_hours,
r.cost_estimate_usd,
r.co2_kg,
r.risk_level,
r.corridor,
r.alternative_available,
po.risk_score           AS port_risk_score,
po.congestion_index     AS port_congestion,
l.lpi_score             AS pays_lpi
FROM fact_routes r
LEFT JOIN dim_pays  p  ON r.country_iso = p.iso3
LEFT JOIN dim_port  po ON r.start_port  = po.port_name
LEFT JOIN fact_lpi  l  ON r.country_iso = l.iso3
ORDER BY r.distance_km;

-- Vue 6 : KPI synthèse globale (tableau de bord)
CREATE OR REPLACE VIEW v_kpi_global AS
SELECT
(SELECT COUNT(*)                        FROM dim_pays)              AS nb_pays,
(SELECT COUNT(*)                        FROM dim_port)              AS nb_ports,
(SELECT ROUND(AVG(lpi_score),2)         FROM fact_lpi)              AS lpi_mondial_moyen,
(SELECT COUNT(*) FROM dim_port
    WHERE risk_score > 0.6)                                            AS ports_critiques,
(SELECT ROUND(AVG(total_transits),0)
    FROM fact_suez WHERE is_crisis = 0)                                AS suez_transit_normal,
(SELECT ROUND(AVG(total_transits),0)
    FROM fact_suez WHERE is_crisis = 1)                                AS suez_transit_crise,
(SELECT ROUND((1 - AVG(CASE WHEN is_crisis=1 THEN total_transits END)
                    / NULLIF(AVG(CASE WHEN is_crisis=0 THEN total_transits END),0)
                ) * 100, 1)
    FROM fact_suez)                                                    AS suez_pct_impact_crise,
(SELECT COUNT(DISTINCT reporter_iso) FROM fact_trade)               AS nb_pays_actifs_trade,
(SELECT ROUND(SUM(trade_value_billion),1)
    FROM fact_trade WHERE year = 2023 AND flow = 'Export')             AS export_mondial_2023_Mrd,
(SELECT COUNT(*) FROM fact_routes WHERE risk_level = 'High')        AS routes_a_haut_risque;
