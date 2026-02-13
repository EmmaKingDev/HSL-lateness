"""
HSL Performance Dashboard - LOCAL VERSION (queries Athena directly)
Run with: streamlit run app_local.py

Use this for testing locally before publishing.
"""
import streamlit as st
import boto3
import pandas as pd
import time
from datetime import datetime

# Config
DATABASE = "hsl_transport"
WORKGROUP = "primary"
REGION = "eu-north-1"
REFRESH_INTERVAL = 300

st.set_page_config(page_title="HSL Late Lines Today", layout="wide", menu_items={})

st.markdown(
    f"""
    <meta http-equiv="refresh" content="{REFRESH_INTERVAL}">
    <style>
        .stDeployButton {{display: none;}}
        #MainMenu {{visibility: hidden;}}
    </style>
    """,
    unsafe_allow_html=True,
)


@st.cache_data(ttl=60)
def run_athena_query(query: str) -> pd.DataFrame:
    client = boto3.client("athena", region_name=REGION)

    response = client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": DATABASE},
        WorkGroup=WORKGROUP,
        ResultConfiguration={
            "OutputLocation": "s3://emkidev-results-hsl/"
        },
    )
    query_id = response["QueryExecutionId"]

    while True:
        result = client.get_query_execution(QueryExecutionId=query_id)
        state = result["QueryExecution"]["Status"]["State"]
        if state == "SUCCEEDED":
            break
        elif state in ("FAILED", "CANCELLED"):
            raise Exception(f"Query {state}")
        time.sleep(0.5)

    paginator = client.get_paginator("get_query_results")
    results = []
    for page in paginator.paginate(QueryExecutionId=query_id):
        for row in page["ResultSet"]["Rows"]:
            results.append([col.get("VarCharValue", "") for col in row["Data"]])

    if len(results) > 1:
        return pd.DataFrame(results[1:], columns=results[0])
    return pd.DataFrame()


today = datetime.now()
year = today.strftime("%Y")
month = today.strftime("%m")
day = today.strftime("%d")

st.title("Which HSL lines are late today?")
st.caption(f"Showing data for {today.strftime('%A, %d %B %Y')} | Auto-refreshes every 5 minutes")

query = f"""
SELECT
    route_short_name,
    ROUND(AVG(delay_seconds) / 60.0, 1) as avg_delay_min
FROM gold_performance
WHERE year = '{year}' AND month = '{month}' AND day = '{day}'
  AND scheduled_arrival IS NOT NULL
  AND route_short_name IS NOT NULL
GROUP BY route_short_name
HAVING AVG(delay_seconds) / 60.0 > 5
ORDER BY avg_delay_min DESC
"""

stats_query = f"""
SELECT
    MIN(from_unixtime(CAST(feed_timestamp AS bigint) + 7200)) as first_feed,
    MAX(from_unixtime(CAST(feed_timestamp AS bigint) + 7200)) as last_feed
FROM silver_realtime
WHERE year = '{year}' AND month = '{month}' AND day = '{day}'
"""

with st.spinner("Querying Athena..."):
    try:
        df = run_athena_query(query)
        stats = run_athena_query(stats_query)
        if not df.empty:
            df["avg_delay_min"] = pd.to_numeric(df["avg_delay_min"])
    except Exception as e:
        st.error(f"Error: {e}")
        st.stop()

if not stats.empty and stats.iloc[0]["first_feed"]:
    first = str(stats.iloc[0]["first_feed"])[11:16]
    last = str(stats.iloc[0]["last_feed"])[11:16]
    st.info(f"Data from {first} → {last}")
else:
    st.warning("No data collected today yet.")
    st.stop()

st.subheader("Routes Running >5 Minutes Late (Average)")

if not df.empty:
    st.bar_chart(df.set_index("route_short_name")["avg_delay_min"], height=500)
    st.caption(f"{len(df)} routes averaging more than 5 minutes late")
else:
    st.success("No routes averaging more than 5 minutes late today!")

st.divider()
st.caption(f"Last updated: {datetime.now().strftime('%H:%M:%S')} | Data from HSL GTFS-realtime API")
