
CREATE INDEX IF NOT EXISTS ix_county_state           ON eda.county (state_id);
CREATE INDEX IF NOT EXISTS ix_zip_county             ON eda.zip_code (primary_county_id);
CREATE INDEX IF NOT EXISTS ix_zip_state              ON eda.zip_code (state_id);

CREATE INDEX IF NOT EXISTS ix_plan_product           ON eda.product_plan (product_id);
CREATE INDEX IF NOT EXISTS ix_rider_plan             ON eda.product_rider (plan_id);


CREATE INDEX IF NOT EXISTS ix_account_zip            ON eda.account (zip_id);
CREATE INDEX IF NOT EXISTS ix_memaddr_member         ON eda.member_address (member_id);
CREATE INDEX IF NOT EXISTS ix_memaddr_zip            ON eda.member_address (zip_id);
CREATE INDEX IF NOT EXISTS ix_memrel_related         ON eda.member_relation (related_member_id);
CREATE INDEX IF NOT EXISTS ix_acctmem_member         ON eda.account_member (member_id);


CREATE INDEX IF NOT EXISTS ix_contract_plan          ON eda.contract (plan_id);
CREATE INDEX IF NOT EXISTS ix_contract_account       ON eda.contract (account_id);
CREATE INDEX IF NOT EXISTS ix_cparty_member          ON eda.contract_party (member_id);
CREATE INDEX IF NOT EXISTS ix_cbenefit_rider         ON eda.contract_benefit (rider_id);
CREATE INDEX IF NOT EXISTS ix_cpremium_contract      ON eda.contract_premium (contract_id);
CREATE INDEX IF NOT EXISTS ix_cpremium_rider         ON eda.contract_premium (rider_id);


CREATE INDEX IF NOT EXISTS ix_provider_zip           ON eda.provider (zip_id);


CREATE INDEX IF NOT EXISTS ix_clinobs_member         ON eda.clinical_observation (member_id);
CREATE INDEX IF NOT EXISTS ix_chroncond_member       ON eda.chronic_condition (member_id);
CREATE INDEX IF NOT EXISTS ix_chroncond_dx           ON eda.chronic_condition (diagnosis_code_id);


CREATE INDEX IF NOT EXISTS ix_geohealth_source       ON eda.geo_health_indicator (source_id);
CREATE INDEX IF NOT EXISTS ix_asset_source           ON eda.unstructured_asset (source_id);
CREATE INDEX IF NOT EXISTS ix_asset_member           ON eda.unstructured_asset (member_id);
CREATE INDEX IF NOT EXISTS ix_asset_contract         ON eda.unstructured_asset (contract_id);

-
CREATE INDEX IF NOT EXISTS ix_geohealth_lookup
    ON eda.geo_health_indicator (county_id, indicator_code, measure_year);


CREATE INDEX IF NOT EXISTS ix_contract_inforce
    ON eda.contract (account_id, effective_date)
    WHERE in_force_flag = TRUE;


CREATE INDEX IF NOT EXISTS ix_account_active
    ON eda.account (zip_id)
    WHERE status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS ix_asset_parsed_gin
    ON eda.unstructured_asset USING GIN (parsed_data);


CREATE INDEX IF NOT EXISTS ix_stg_places_tract   ON eda.staging_places_tract (tract_fips);
CREATE INDEX IF NOT EXISTS ix_stg_places_measure ON eda.staging_places_tract (measure_id);
CREATE INDEX IF NOT EXISTS ix_stg_svi_tract      ON eda.staging_svi_tract (tract_fips);
CREATE INDEX IF NOT EXISTS ix_stg_svi_county     ON eda.staging_svi_tract (county_fips);



ALTER TABLE eda.unstructured_asset
    DROP CONSTRAINT IF EXISTS unstructured_asset_claim_id_fkey;


DROP TABLE IF EXISTS eda.claim_diagnosis;
DROP TABLE IF EXISTS eda.claim_line;
DROP TABLE IF EXISTS eda.claim;


CREATE TABLE eda.claim (
    claim_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    service_year    SMALLINT NOT NULL,
    claim_number    VARCHAR(24) NOT NULL,
    contract_id     BIGINT NOT NULL REFERENCES eda.contract(contract_id),
    member_id       BIGINT NOT NULL REFERENCES eda.member(member_id),
    provider_id     BIGINT REFERENCES eda.provider(provider_id),
    claim_date      DATE NOT NULL,
    admission_date  DATE,
    discharge_date  DATE,
    settlement_date DATE,
    status          eda.claim_status NOT NULL DEFAULT 'SUBMITTED',
    billed_amount   NUMERIC(14,2),
    allowed_amount  NUMERIC(14,2),
    paid_amount     NUMERIC(14,2),
    is_readmission  BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (claim_id, service_year),
    UNIQUE (claim_number, service_year)
) PARTITION BY RANGE (service_year);

CREATE TABLE eda.claim_y2022 PARTITION OF eda.claim FOR VALUES FROM (2022) TO (2023);
CREATE TABLE eda.claim_y2023 PARTITION OF eda.claim FOR VALUES FROM (2023) TO (2024);
CREATE TABLE eda.claim_y2024 PARTITION OF eda.claim FOR VALUES FROM (2024) TO (2025);
CREATE TABLE eda.claim_y2025 PARTITION OF eda.claim FOR VALUES FROM (2025) TO (2026);
CREATE TABLE eda.claim_y2026 PARTITION OF eda.claim FOR VALUES FROM (2026) TO (2027);

CREATE TABLE eda.claim_ydefault PARTITION OF eda.claim DEFAULT;


CREATE TABLE eda.claim_line (
    claim_line_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    claim_id         BIGINT NOT NULL,
    service_year     SMALLINT NOT NULL,
    line_number      SMALLINT NOT NULL,
    procedure_system eda.code_system,
    procedure_code   VARCHAR(12),
    revenue_code     VARCHAR(8),
    service_from     DATE,
    service_to       DATE,
    units            NUMERIC(10,2),
    billed_amount    NUMERIC(14,2),
    allowed_amount   NUMERIC(14,2),
    paid_amount      NUMERIC(14,2),
    place_of_service VARCHAR(8),
    PRIMARY KEY (claim_line_id, service_year),
    UNIQUE (claim_id, line_number, service_year),
    FOREIGN KEY (claim_id, service_year)
        REFERENCES eda.claim (claim_id, service_year)
) PARTITION BY RANGE (service_year);

CREATE TABLE eda.claim_line_y2022 PARTITION OF eda.claim_line FOR VALUES FROM (2022) TO (2023);
CREATE TABLE eda.claim_line_y2023 PARTITION OF eda.claim_line FOR VALUES FROM (2023) TO (2024);
CREATE TABLE eda.claim_line_y2024 PARTITION OF eda.claim_line FOR VALUES FROM (2024) TO (2025);
CREATE TABLE eda.claim_line_y2025 PARTITION OF eda.claim_line FOR VALUES FROM (2025) TO (2026);
CREATE TABLE eda.claim_line_y2026 PARTITION OF eda.claim_line FOR VALUES FROM (2026) TO (2027);
CREATE TABLE eda.claim_line_ydefault PARTITION OF eda.claim_line DEFAULT;


CREATE TABLE eda.claim_diagnosis (
    claim_id          BIGINT NOT NULL,
    service_year      SMALLINT NOT NULL,
    diagnosis_code_id INTEGER NOT NULL REFERENCES eda.diagnosis_code(diagnosis_code_id),
    sequence_number   SMALLINT NOT NULL,
    poa_indicator     CHARACTER(1),
    PRIMARY KEY (claim_id, diagnosis_code_id, sequence_number, service_year),
    FOREIGN KEY (claim_id, service_year)
        REFERENCES eda.claim (claim_id, service_year)
) PARTITION BY RANGE (service_year);

CREATE TABLE eda.claim_diagnosis_y2022 PARTITION OF eda.claim_diagnosis FOR VALUES FROM (2022) TO (2023);
CREATE TABLE eda.claim_diagnosis_y2023 PARTITION OF eda.claim_diagnosis FOR VALUES FROM (2023) TO (2024);
CREATE TABLE eda.claim_diagnosis_y2024 PARTITION OF eda.claim_diagnosis FOR VALUES FROM (2024) TO (2025);
CREATE TABLE eda.claim_diagnosis_y2025 PARTITION OF eda.claim_diagnosis FOR VALUES FROM (2025) TO (2026);
CREATE TABLE eda.claim_diagnosis_y2026 PARTITION OF eda.claim_diagnosis FOR VALUES FROM (2026) TO (2027);
CREATE TABLE eda.claim_diagnosis_ydefault PARTITION OF eda.claim_diagnosis DEFAULT;


ALTER TABLE eda.unstructured_asset
    ADD CONSTRAINT unstructured_asset_claim_fkey
    FOREIGN KEY (claim_id, service_year)
        REFERENCES eda.claim (claim_id, service_year);


CREATE INDEX IF NOT EXISTS ix_claim_member    ON eda.claim (member_id);
CREATE INDEX IF NOT EXISTS ix_claim_contract  ON eda.claim (contract_id);
CREATE INDEX IF NOT EXISTS ix_claim_provider  ON eda.claim (provider_id);

CREATE INDEX IF NOT EXISTS ix_claim_member_date ON eda.claim (member_id, claim_date DESC);

CREATE INDEX IF NOT EXISTS ix_claimdx_dx      ON eda.claim_diagnosis (diagnosis_code_id);


CLUSTER eda.geo_health_indicator USING ix_geohealth_lookup;


ALTER TABLE eda.geo_health_indicator CLUSTER ON ix_geohealth_lookup;



DROP MATERIALIZED VIEW IF EXISTS eda.county_risk_profile;

CREATE MATERIALIZED VIEW eda.county_risk_profile AS
SELECT
    c.county_id,
    c.county_fips,
    c.county_name,
    s.state_code,

    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'DIABETES')   AS diabetes_pct,
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'OBESITY')    AS obesity_pct,
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'BPHIGH')     AS high_bp_pct,
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'CHD')        AS chd_pct,
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'STROKE')     AS stroke_pct,
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'COPD')       AS copd_pct,
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'CANCER')     AS cancer_pct,

    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'CSMOKING')   AS smoking_pct,
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'LPA')        AS no_phys_activity_pct,
    
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'SVI_OVERALL') AS svi_overall,
  
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'AQI_MEDIAN')          AS aqi_median,
    max(g.value_numeric) FILTER (WHERE g.indicator_code = 'AQI_UNHEALTHY_DAYS')  AS aqi_unhealthy_days,
    
    max(g.measure_year)  AS latest_measure_year,
    count(*)             AS indicator_count
FROM eda.county c
JOIN eda.state s          ON s.state_id  = c.state_id
LEFT JOIN eda.geo_health_indicator g ON g.county_id = c.county_id
GROUP BY c.county_id, c.county_fips, c.county_name, s.state_code;

-
CREATE UNIQUE INDEX ix_county_risk_profile_pk
    ON eda.county_risk_profile (county_id);
CREATE INDEX ix_county_risk_profile_fips
    ON eda.county_risk_profile (county_fips);


ANALYZE eda.geo_health_indicator;
ANALYZE eda.staging_places_tract;
ANALYZE eda.staging_svi_tract;
ANALYZE eda.staging_aqi_county;
ANALYZE eda.county;
ANALYZE eda.contract;
ANALYZE eda.account;


