

import argparse
import hashlib
import time
from datetime import datetime
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text


DB_URL = "postgresql+psycopg://postgres:YOUR_PASSWORD@localhost:5432/insurancecomp2_eda"

DATA_DIR = Path(__file__).parent / "Data"

SOURCES = {
    "SVI": {
        "catalog_like": "CDC/ATSDR Social Vulnerability%",
        "file": DATA_DIR / "svi_ny_tract.csv",
        "table": "eda.staging_svi_tract",
    },
    "PLACES": {
        "catalog_like": "CDC PLACES%",
        "file": DATA_DIR / "places_ny_chronic.csv",
        "table": "eda.staging_places_tract",
    },
    "AQI": {
        "catalog_like": "EPA Annual AQI%",
        "file": DATA_DIR / "aqi_ny_county.csv",
        "table": "eda.staging_aqi_county",
    },
}


FEATURES = [
    "ep_pov150", "ep_unemp", "ep_hburd", "ep_nohsdp", "ep_uninsur",
    "ep_age65", "ep_age17", "ep_crowd", "ep_noveh", "ep_noint",
]
TARGETS = ["diabetes", "obesity", "bphigh", "chd", "stroke", "copd", "cancer"]
PRIMARY_TARGET = "diabetes"
N_TIERS = 4


def log(msg, indent=0):
    print(f"  [{datetime.now():%H:%M:%S}] {'  ' * indent}{msg}", flush=True)



def fingerprint(path: Path):
    """SHA-256 hash and row count of a source file.

    Hashing the contents rather than checking a modified timestamp means
    a file re-downloaded unchanged will not trigger a needless re-train,
    while a file edited in place is still detected.
    """
    h = hashlib.sha256()
    rows = 0
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
            rows += chunk.count(b"\n")
    return h.hexdigest(), max(rows - 1, 0)


def detect_changes(conn):
    changed = []

    for key, cfg in SOURCES.items():
        if not cfg["file"].exists():
            log(f"{key}: file not found at {cfg['file']} - skipped", 1)
            continue

        checksum, rows = fingerprint(cfg["file"])

        source_id = conn.execute(
            text("SELECT source_id FROM eda.data_source_catalog "
                 "WHERE source_name LIKE :pat LIMIT 1"),
            {"pat": cfg["catalog_like"]},
        ).scalar()

        if source_id is None:
            log(f"{key}: not registered in data_source_catalog - skipped", 1)
            continue

        prior = conn.execute(
            text("SELECT checksum_sha256 FROM eda.source_fingerprint "
                 "WHERE source_id = :sid"),
            {"sid": source_id},
        ).scalar()

        if prior is None:
            log(f"{key}: no prior fingerprint, treating as changed ({rows:,} rows)", 1)
            changed.append(key)
        elif prior.strip() != checksum:
            log(f"{key}: CHANGED ({rows:,} rows)", 1)
            changed.append(key)
        else:
            log(f"{key}: unchanged", 1)

        conn.execute(text("""
            INSERT INTO eda.source_fingerprint
                (source_id, file_path, checksum_sha256, row_count)
            VALUES (:sid, :path, :sum, :rows)
            ON CONFLICT (source_id) DO UPDATE SET
                checksum_sha256 = EXCLUDED.checksum_sha256,
                row_count       = EXCLUDED.row_count,
                last_checked_at = now()
        """), {"sid": source_id, "path": str(cfg["file"]),
               "sum": checksum, "rows": rows})

    conn.commit()
    return changed

STRING_COLUMNS = {
    "SVI":    ["county_fips", "county_name", "tract_fips"],
    "PLACES": ["county_fips", "tract_fips", "measure_id", "measure_name", "unit"],
    "AQI":    ["county_name"],
}

def restage(engine, conn, key):
    
    """ cfg = SOURCES[key]
    df = pd.read_csv(cfg["file"], dtype=str)

    conn.execute(text(f"TRUNCATE TABLE {cfg['table']}"))
    conn.commit()

    schema, name = cfg["table"].split(".")
    df.to_sql(name, engine, schema=schema, if_exists="append", index=False)
    log(f"{key}: reloaded {len(df):,} rows into {cfg['table']}", 1) """

    cfg = SOURCES[key]
    df = pd.read_csv(cfg["file"], dtype={c: str for c in STRING_COLUMNS[key]})

    conn.execute(text(f"TRUNCATE TABLE {cfg['table']}"))
    conn.commit()

    schema, name = cfg["table"].split(".")
    df.to_sql(name, engine, schema=schema, if_exists="append", index=False)
    log(f"{key}: reloaded {len(df):,} rows into {cfg['table']}", 1)



AGGREGATIONS = {
    "SVI": """
        INSERT INTO eda.geo_health_indicator
            (county_id, source_id, indicator_code, indicator_name,
             measure_year, value_numeric, unit)
        SELECT c.county_id,
               (SELECT source_id FROM eda.data_source_catalog
                 WHERE source_name LIKE 'CDC/ATSDR Social Vulnerability%' LIMIT 1),
               'SVI_OVERALL',
               'Overall Social Vulnerability Index (percentile rank)',
               2025,
               ROUND(SUM(s.rpl_themes::numeric * s.total_pop::numeric)
                     / NULLIF(SUM(s.total_pop::numeric), 0), 4),
               'percentile'
        FROM eda.staging_svi_tract s
        JOIN eda.county c ON c.county_fips = s.county_fips
        WHERE s.rpl_themes IS NOT NULL
        GROUP BY c.county_id
    """,
    "PLACES": """
        INSERT INTO eda.geo_health_indicator
            (county_id, source_id, indicator_code, indicator_name,
             measure_year, value_numeric, unit)
        SELECT c.county_id,
               (SELECT source_id FROM eda.data_source_catalog
                 WHERE source_name LIKE 'CDC PLACES%' LIMIT 1),
               p.measure_id, max(p.measure_name), p.year::smallint,
               ROUND(SUM(p.data_value::numeric * p.total_pop::numeric)
                     / NULLIF(SUM(p.total_pop::numeric), 0), 2),
               max(p.unit)
        FROM eda.staging_places_tract p
        JOIN eda.county c ON c.county_fips = p.county_fips
        WHERE p.data_value IS NOT NULL
        GROUP BY c.county_id, p.measure_id, p.year
    """,
    "AQI": """
        INSERT INTO eda.geo_health_indicator
            (county_id, source_id, indicator_code, indicator_name,
             measure_year, value_numeric, unit)
        SELECT c.county_id,
               (SELECT source_id FROM eda.data_source_catalog
                 WHERE source_name LIKE 'EPA Annual AQI%' LIMIT 1),
               'AQI_MEDIAN', 'Median Air Quality Index',
               a.year::smallint, a.median_aqi::numeric, 'AQI'
        FROM eda.staging_aqi_county a
        JOIN eda.county c ON c.county_name = a.county_name || ' County'
        WHERE a.median_aqi IS NOT NULL
    """,
}


def reaggregate(conn):
    
    conn.execute(text("TRUNCATE TABLE eda.geo_health_indicator CASCADE"))
    total = 0
    for name, sql in AGGREGATIONS.items():
        result = conn.execute(text(sql))
        total += result.rowcount or 0
        log(f"{name}: {result.rowcount} indicator rows", 1)
    conn.commit()

    try:
        conn.execute(text(
            "REFRESH MATERIALIZED VIEW CONCURRENTLY eda.county_risk_profile"))
    except Exception:
        conn.execute(text("REFRESH MATERIALIZED VIEW eda.county_risk_profile"))
    conn.commit()
    log("refreshed county_risk_profile", 1)
    return total




def build_features(conn):
    """Assemble the tract-level feature table from the staging tables.

    Predictors come from SVI (Census-derived); the target comes from
    PLACES. Keeping them in separate source systems is deliberate:
    PLACES values are themselves small-area model estimates, so
    predicting one PLACES measure from another would partly mean
    predicting a model's output from its own other outputs.
    """
    svi = pd.read_sql(text("SELECT * FROM eda.staging_svi_tract"), conn)
    places = pd.read_sql(text(
        "SELECT tract_fips, measure_id, data_value "
        "FROM eda.staging_places_tract"), conn)

    for col in svi.columns:
        if col not in ("tract_fips", "county_fips", "county_name"):
            svi[col] = pd.to_numeric(svi[col], errors="coerce")

    places["data_value"] = pd.to_numeric(places["data_value"], errors="coerce")
    wide = places.pivot_table(index="tract_fips", columns="measure_id",
                              values="data_value", aggfunc="first")
    wide.columns = [c.lower() for c in wide.columns]

    return svi.merge(wide.reset_index(), on="tract_fips", how="inner")


def retrain(engine, conn):
    
    from sklearn.model_selection import train_test_split
    from sklearn.ensemble import RandomForestRegressor
    from sklearn.preprocessing import StandardScaler
    from sklearn.cluster import KMeans
    from sklearn.metrics import r2_score, mean_absolute_error

    df = build_features(conn)
    log(f"feature table: {len(df):,} tracts", 1)

    feats = [f for f in FEATURES if f in df.columns]
    d = df.dropna(subset=feats + [PRIMARY_TARGET])
    log(f"usable rows after dropping incomplete: {len(d):,}", 1)

    
    X_tr, X_te, y_tr, y_te = train_test_split(
        d[feats], d[PRIMARY_TARGET], test_size=0.25, random_state=42)
    rf = RandomForestRegressor(n_estimators=200, random_state=42,
                               n_jobs=-1).fit(X_tr, y_tr)
    pred = rf.predict(X_te)
    log(f"random forest retrained: R2={r2_score(y_te, pred):.3f}  "
        f"MAE={mean_absolute_error(y_te, pred):.2f}pp", 1)

    
    present = [t for t in TARGETS if t in d.columns]
    cty = (d.groupby("county_fips")[feats + present]
             .mean().dropna(subset=feats).reset_index())

    km = KMeans(n_clusters=N_TIERS, random_state=42, n_init=10).fit(
        StandardScaler().fit_transform(cty[feats]))
    cty["cluster"] = km.labels_

   
    order = cty.groupby("cluster")[PRIMARY_TARGET].mean().sort_values().index
    cty["risk_tier"] = cty["cluster"].map({c: i + 1 for i, c in enumerate(order)})
    log(f"clustered {len(cty)} counties into {N_TIERS} risk tiers", 1)

   
    names = dict(conn.execute(text(
        "SELECT county_fips, county_name FROM eda.county")).fetchall())

    out = pd.DataFrame({
        "county_fips": cty["county_fips"],
        "county_name": cty["county_fips"].map(names),
        "risk_tier": cty["risk_tier"].astype(int),
    })
    for t in TARGETS:
        out[t] = cty[t].round(2) if t in cty.columns else None

    conn.execute(text("TRUNCATE TABLE eda.county_risk_tier"))
    conn.commit()
    out.to_sql("county_risk_tier", engine, schema="eda",
               if_exists="append", index=False)
    log(f"reloaded county_risk_tier with {len(out)} counties", 1)



def run(force=False):
    engine = create_engine(DB_URL)
    started = time.time()

    with engine.connect() as conn:
        log("stage 1: checking sources for changes")
        changed = detect_changes(conn)

        if not changed and not force:
            log("no source changes detected - re-training skipped")
            log(f"done in {time.time() - started:.1f}s")
            return "NO_CHANGE"

        targets = changed if changed else list(SOURCES)
        log(f"stage 2: re-staging {len(targets)} source(s)")
        for key in targets:
            restage(engine, conn, key)

        log("stage 3: re-aggregating to county grain")
        reaggregate(conn)

        log("stage 4: re-training model")
        retrain(engine, conn)

        log(f"pipeline complete in {time.time() - started:.1f}s")
        return "SUCCESS"


if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Part 4 data-driven pipeline module")
    ap.add_argument("--force", action="store_true",
                    help="re-train even if no source change is detected")
    args = ap.parse_args()

    print("=" * 62)
    print("  Data-Driven Pipeline Module")
    print("=" * 62)
    status = run(force=args.force)
    print("=" * 62)
    print(f"  result: {status}")
    print("=" * 62)
