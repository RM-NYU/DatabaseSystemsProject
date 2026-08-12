

DROP TABLE IF EXISTS eda.stg_synthea_patient;
DROP TABLE IF EXISTS eda.stg_synthea_provider;
DROP TABLE IF EXISTS eda.stg_synthea_claim;
DROP TABLE IF EXISTS eda.stg_synthea_dxcode;
DROP TABLE IF EXISTS eda.stg_synthea_claimdx;
DROP TABLE IF EXISTS eda.stg_synthea_chronic;

CREATE TABLE eda.stg_synthea_patient (
    synthea_id      VARCHAR(40),
    last_name       VARCHAR(60),
    first_name      VARCHAR(60),
    middle_initial  CHARACTER(1),
    dob             DATE,
    sex             VARCHAR(1),
    county_fips     VARCHAR(5),
    zip5            VARCHAR(5),
    city            VARCHAR(80),
    address1        VARCHAR(120),
    deceased_date   DATE
);

CREATE TABLE eda.stg_synthea_provider (
    synthea_provider_id VARCHAR(40),
    npi                 VARCHAR(10),
    provider_name       VARCHAR(160)
);

CREATE TABLE eda.stg_synthea_claim (
    synthea_claim_id    VARCHAR(40),
    synthea_patient_id  VARCHAR(40),
    synthea_provider_id VARCHAR(40),
    service_year        SMALLINT,
    claim_date          DATE,
    status              VARCHAR(20),
    billed_amount       NUMERIC(14,2),
    allowed_amount      NUMERIC(14,2),
    paid_amount         NUMERIC(14,2)
);

CREATE TABLE eda.stg_synthea_dxcode (
    code             VARCHAR(20),
    short_desc       VARCHAR(200),
    is_chronic       BOOLEAN,
    condition_family VARCHAR(60)
);

CREATE TABLE eda.stg_synthea_claimdx (
    synthea_claim_id VARCHAR(40),
    service_year     SMALLINT,
    code             VARCHAR(20),
    sequence_number  SMALLINT
);

CREATE TABLE eda.stg_synthea_chronic (
    synthea_patient_id VARCHAR(40),
    code               VARCHAR(20),
    onset_date         DATE,
    resolved_date      DATE
);



INSERT INTO eda.zip_code (zip5, primary_county_id, state_id)
SELECT DISTINCT ON (p.zip5)
       p.zip5,
       c.county_id,
       c.state_id
FROM eda.stg_synthea_patient p
JOIN eda.county c ON c.county_fips = p.county_fips
WHERE p.zip5 IS NOT NULL
  AND p.zip5 <> '00000'
  AND p.county_fips LIKE '36%'
ORDER BY p.zip5, c.county_id
ON CONFLICT (zip5) DO NOTHING;


INSERT INTO eda.member
    (cust_last_name, cust_first_name, cust_middle_initial, cust_dob, sex,
     legacy_customer_id, deceased_date)
SELECT p.last_name,
       p.first_name,
       p.middle_initial,
       p.dob,
       p.sex::eda.sex_at_birth,
       p.synthea_id,          
       p.deceased_date
FROM eda.stg_synthea_patient p
ON CONFLICT DO NOTHING;


INSERT INTO eda.member_address
    (member_id, address_line1, city, zip_id, effective_from)
SELECT m.member_id,
       p.address1,
       p.city,
       z.zip_id,
       COALESCE(p.dob, DATE '2000-01-01')
FROM eda.stg_synthea_patient p
JOIN eda.member   m ON m.legacy_customer_id = p.synthea_id
JOIN eda.zip_code z ON z.zip5 = p.zip5;

INSERT INTO eda.provider (npi, provider_name, is_aco)
SELECT sp.npi, sp.provider_name, FALSE
FROM eda.stg_synthea_provider sp
ON CONFLICT (npi) DO NOTHING;


INSERT INTO eda.diagnosis_code
    (system, code, short_desc, is_chronic, condition_family)
SELECT 'SNOMED'::eda.code_system,
       d.code,
       d.short_desc,
       d.is_chronic,
       NULLIF(d.condition_family, '')
FROM eda.stg_synthea_dxcode d
ON CONFLICT (system, code) DO NOTHING;



INSERT INTO eda.product (line_of_business, description)
VALUES ('HEALTH', 'Group health coverage (Synthea demonstration line of business)')
ON CONFLICT DO NOTHING;

INSERT INTO eda.product_plan (product_id, series_name, plan_name, plan_code, description)
SELECT p.product_id, 'NY-GROUP-2022', 'NY Group Health Standard', 'NYGHS',
       'Standard NY group health plan used for the Synthea demonstration population'
FROM eda.product p
WHERE p.line_of_business = 'HEALTH'
ON CONFLICT DO NOTHING;

INSERT INTO eda.product_rider (plan_id, rider_name, description, annualized_premium)
SELECT pp.plan_id, 'BASE', 'Base medical benefit', 0.00
FROM eda.product_plan pp
WHERE pp.plan_name = 'NY Group Health Standard'
ON CONFLICT DO NOTHING;


INSERT INTO eda.account
    (account_name, company_code, location_city, zip_id, status, number_of_employees)
SELECT DISTINCT ON (c.county_id)
       c.county_name || ' Regional Employer Group',
       'SYN',
       c.county_name,
       z.zip_id,
       'ACTIVE'::eda.activity_status,
       NULL
FROM eda.stg_synthea_patient p
JOIN eda.county   c ON c.county_fips = p.county_fips
JOIN eda.zip_code z ON z.primary_county_id = c.county_id
ORDER BY c.county_id, z.zip_id
ON CONFLICT DO NOTHING;


INSERT INTO eda.account_member (account_id, member_id, effective_from)
SELECT a.account_id, m.member_id, DATE '2022-01-01'
FROM eda.stg_synthea_patient p
JOIN eda.member m ON m.legacy_customer_id = p.synthea_id
JOIN eda.county c ON c.county_fips = p.county_fips
JOIN eda.account a ON a.account_name = c.county_name || ' Regional Employer Group'
ON CONFLICT DO NOTHING;


INSERT INTO eda.contract
    (contract_number, plan_id, account_id, status, coverage_type,
     billing_method, modal_premium, effective_date, in_force_flag,
     deductible_amount, oop_maximum)
SELECT 'SYN-' || lpad(m.member_id::text, 8, '0'),
       pp.plan_id,
       am.account_id,
       'ACTIVE'::eda.activity_status,
       'INDIVIDUAL',
       'GROUP_BILL',
       450.00,
       DATE '2022-01-01',
       TRUE,
       1500.00,
       6000.00
FROM eda.member m
JOIN eda.account_member am ON am.member_id = m.member_id
CROSS JOIN (SELECT plan_id FROM eda.product_plan WHERE plan_name = 'NY Group Health Standard' LIMIT 1) pp
WHERE m.legacy_customer_id IS NOT NULL
ON CONFLICT (contract_number) DO NOTHING;


INSERT INTO eda.contract_party (contract_id, member_id, role, effective_from)
SELECT ct.contract_id, m.member_id, 'INSURED'::eda.party_role, DATE '2022-01-01'
FROM eda.contract ct
JOIN eda.member m ON ct.contract_number = 'SYN-' || lpad(m.member_id::text, 8, '0')
ON CONFLICT DO NOTHING;



INSERT INTO eda.claim
    (service_year, claim_number, contract_id, member_id, provider_id,
     claim_date, status, billed_amount, allowed_amount, paid_amount)
SELECT sc.service_year,
       left(sc.synthea_claim_id, 24),
       ct.contract_id,
       m.member_id,
       pr.provider_id,
       sc.claim_date,
       sc.status::eda.claim_status,
       sc.billed_amount,
       sc.allowed_amount,
       sc.paid_amount
FROM eda.stg_synthea_claim sc
JOIN eda.member m  ON m.legacy_customer_id = sc.synthea_patient_id
JOIN eda.contract ct ON ct.contract_number = 'SYN-' || lpad(m.member_id::text, 8, '0')
LEFT JOIN eda.stg_synthea_provider sp ON sp.synthea_provider_id = sc.synthea_provider_id
LEFT JOIN eda.provider pr ON pr.npi = sp.npi
ON CONFLICT (claim_number, service_year) DO NOTHING;


INSERT INTO eda.claim_diagnosis
    (claim_id, service_year, diagnosis_code_id, sequence_number)
SELECT cl.claim_id,
       cl.service_year,
       dc.diagnosis_code_id,
       cdx.sequence_number
FROM eda.stg_synthea_claimdx cdx
JOIN eda.claim cl
      ON cl.claim_number = left(cdx.synthea_claim_id, 24)
     AND cl.service_year = cdx.service_year
JOIN eda.diagnosis_code dc
      ON dc.code = cdx.code AND dc.system = 'SNOMED'
ON CONFLICT DO NOTHING;


INSERT INTO eda.chronic_condition
    (member_id, diagnosis_code_id, onset_date, resolved_date,
     confidence, derived_from)
SELECT m.member_id,
       dc.diagnosis_code_id,
       ch.onset_date,
       ch.resolved_date,
       1.000,
       'SYNTHEA_CONDITIONS'
FROM eda.stg_synthea_chronic ch
JOIN eda.member m ON m.legacy_customer_id = ch.synthea_patient_id
JOIN eda.diagnosis_code dc ON dc.code = ch.code AND dc.system = 'SNOMED'
ON CONFLICT DO NOTHING;


ANALYZE eda.member;
ANALYZE eda.member_address;
ANALYZE eda.provider;
ANALYZE eda.account;
ANALYZE eda.account_member;
ANALYZE eda.contract;
ANALYZE eda.contract_party;
ANALYZE eda.diagnosis_code;
ANALYZE eda.claim;
ANALYZE eda.claim_diagnosis;
ANALYZE eda.chronic_condition;


