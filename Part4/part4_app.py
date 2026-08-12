# Ronojoy Mitra
# run with  streamlit run part4_app.py


from datetime import date

import pandas as pd
import streamlit as st
from sqlalchemy import create_engine, text

DB_URL = "postgresql+psycopg://postgres:postgres@localhost:5432/insurancecomp2_eda"
engine = create_engine(DB_URL)

BASE_MONTHLY = 380.00

st.title("Quote to Policy")



def resolve_county(zip5):
    sql = text("""
        SELECT c.county_id, c.county_name, z.zip_id,
               rt.risk_tier, rt.diabetes, rt.obesity
        FROM eda.zip_code z
        JOIN eda.county c ON c.county_id = z.primary_county_id
        LEFT JOIN eda.county_risk_tier rt ON rt.county_fips = c.county_fips
        WHERE z.zip5 = :zip
    """)
    with engine.connect() as conn:
        row = conn.execute(sql, {"zip": zip5}).mappings().first()
    return dict(row) if row else None


def load_plans():
    with engine.connect() as conn:
        return pd.read_sql(
            text("SELECT plan_id, plan_name FROM eda.product_plan ORDER BY plan_name"),
            conn)



def age_factor(age):
    if age < 30:
        return 0.85
    if age < 40:
        return 1.00
    if age < 50:
        return 1.25
    if age < 60:
        return 1.60
    return 2.10



def issue_policy(first, last, dob, sex, address, county, plan_id, monthly):
    with engine.begin() as conn:
        member_id = conn.execute(text("""
            INSERT INTO eda.member
                (cust_last_name, cust_first_name, cust_dob, sex)
            VALUES (:last, :first, :dob, :sex)
            RETURNING member_id
        """), {"last": last, "first": first, "dob": dob, "sex": sex}).scalar()

        if county:
            conn.execute(text("""
                INSERT INTO eda.member_address
                    (member_id, address_line1, city, zip_id, effective_from)
                VALUES (:mid, :addr, :city, :zip, :eff)
            """), {"mid": member_id, "addr": address,
                   "city": county["county_name"], "zip": county["zip_id"],
                   "eff": date.today()})

        account_id = conn.execute(text(
            "SELECT account_id FROM eda.account ORDER BY account_id LIMIT 1"
        )).scalar()

        contract_number = f"QTE-{member_id:08d}"
        contract_id = conn.execute(text("""
            INSERT INTO eda.contract
                (contract_number, plan_id, account_id, status, coverage_type,
                 billing_method, modal_premium, effective_date, in_force_flag)
            VALUES (:num, :plan, :acct, 'ACTIVE', 'INDIVIDUAL', 'DIRECT_BILL',
                    :prem, :eff, TRUE)
            RETURNING contract_id
        """), {"num": contract_number, "plan": plan_id, "acct": account_id,
               "prem": monthly, "eff": date.today()}).scalar()

        conn.execute(text("""
            INSERT INTO eda.contract_party
                (contract_id, member_id, role, effective_from)
            VALUES (:cid, :mid, 'INSURED', :eff)
        """), {"cid": contract_id, "mid": member_id, "eff": date.today()})

        conn.execute(text("""
            INSERT INTO eda.contract_premium
                (contract_id, premium_code, annualized_premium,
                 process_date, app_sign_date)
            VALUES (:cid, 'BASE', :amt, :d, :d)
        """), {"cid": contract_id, "amt": round(monthly * 12, 2),
               "d": date.today()})

    return contract_number, contract_id, member_id



st.header("1. Applicant details")

col1, col2 = st.columns(2)
first = col1.text_input("First name")
last = col2.text_input("Last name")
dob = col1.date_input("Date of birth", value=date(1985, 1, 1),
                      min_value=date(1920, 1, 1), max_value=date.today())
sex = col2.selectbox("Sex at birth", ["M", "F", "U"])
address = st.text_input("Street address")
zip5 = st.text_input("ZIP code", max_chars=5)

plans = load_plans()
plan_id = st.selectbox(
    "Plan", plans.plan_id,
    format_func=lambda i: plans.set_index("plan_id").loc[i, "plan_name"])

if st.button("Get quote", type="primary"):
    if not (first and last and zip5):
        st.error("First name, last name and ZIP code are required.")
        st.stop()

  
    st.header("2. Geographic risk context")
    county = resolve_county(zip5)

    if county is None:
        st.warning(f"ZIP {zip5} did not resolve to a known county. "
                   "Proceeding without county risk context.")
    else:
        st.write(f"**County:** {county['county_name']}")
        st.write(f"**Risk tier:** {county['risk_tier']}   "
                 f"**Diabetes prevalence:** {county['diabetes']}%")
        if county["risk_tier"] and int(county["risk_tier"]) >= 3:
            st.info("Higher-burden county. Wellness and chronic-condition "
                    "riders are worth offering.")
        st.caption("Risk tier is advisory. It informs which products to "
                   "recommend and is not used in the premium calculation.")

  
    st.header("3. Quote")
    age = date.today().year - dob.year - (
        (date.today().month, date.today().day) < (dob.month, dob.day))
    factor = age_factor(age)
    monthly = round(BASE_MONTHLY * factor, 2)

    st.write(f"Base rate ${BASE_MONTHLY:,.2f} × age factor {factor:.2f} "
             f"(age {age})")
    st.write(f"### ${monthly:,.2f} per month")


    decision = "REFERRED" if age >= 70 else "APPROVED"
    if decision == "APPROVED":
        st.success("Automated underwriting: APPROVED")
    else:
        st.warning("Automated underwriting: REFERRED to an underwriter. "
                   "Applications failing the automated rules are reviewed by "
                   "a person rather than declined automatically.")

   
    st.header("4. Policy")
    if decision == "APPROVED":
        try:
            num, cid, mid = issue_policy(first, last, dob, sex, address,
                                         county, int(plan_id), monthly)
            st.success(f"Policy issued: **{num}**")
            st.write(f"Contract ID {cid} · Member ID {mid}")
            st.caption("Written to member, member_address, contract, "
                       "contract_party and contract_premium in one "
                       "transaction.")
        except Exception as exc:
            st.error(f"Policy issue failed, nothing was written: {exc}")
    else:
        st.write("Policy not issued pending underwriter review.")



st.divider()
st.header("Risk model pipeline")
st.caption("The module checks whether the unstructured sources have changed "
           "and re-trains the model only if they have.")

with engine.connect() as conn:
    tiers = pd.read_sql(text("""
        SELECT risk_tier, count(*) AS counties,
               round(avg(diabetes), 2) AS avg_diabetes
        FROM eda.county_risk_tier
        GROUP BY risk_tier ORDER BY risk_tier
    """), conn)
st.dataframe(tiers, use_container_width=True)

if st.button("Run pipeline module"):
    import subprocess, sys
    with st.spinner("Running..."):
        proc = subprocess.run([sys.executable, "part4_pipeline.py"],
                              capture_output=True, text=True)
    st.code(proc.stdout or proc.stderr)
