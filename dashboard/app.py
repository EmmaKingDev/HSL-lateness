"""
HSL Performance Dashboard - Which lines are late today?
Run with: streamlit run app.py

This version reads pre-computed stats from S3 (no AWS credentials needed).
"""
import streamlit as st
import requests
import pandas as pd
import altair as alt
from datetime import datetime

# Config
STATS_URL = "https://emkidev-results-hsl.s3.eu-north-1.amazonaws.com/public/latest.json"
REFRESH_INTERVAL = 300  # Auto-refresh every 5 minutes

st.set_page_config(page_title="HSL Late Lines", layout="wide", menu_items={})

# Auto-refresh + hide deploy button
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

st.title("Which HSL lines are late?")

# Fetch pre-computed stats
try:
    response = requests.get(STATS_URL, timeout=10)
    response.raise_for_status()
    data = response.json()
except requests.exceptions.RequestException as e:
    st.error("Stats not available yet. The daily stats job may not have run.")
    st.info("Stats are generated daily at 00:05 UTC for the previous day's data.")
    st.stop()

# Display metadata
date = data.get("date", "Unknown")
time_range = data.get("time_range", {})
time_from = time_range.get("from", "")[-5:] if time_range.get("from") else ""  # HH:MM
time_to = time_range.get("to", "")[-5:] if time_range.get("to") else ""

st.caption(f"Data from {date} ({time_from} → {time_to})")

# Main chart
st.subheader("Routes Running >5 Minutes Late (Average)")

late_routes = data.get("late_routes", [])

if late_routes:
    df = pd.DataFrame(late_routes)
    df = df.rename(columns={"route": "route_short_name", "avg_delay_min": "avg_delay_min"})

    chart = alt.Chart(df).mark_bar().encode(
        x=alt.X("route_short_name:N",
                title="Route",
                axis=alt.Axis(labelAngle=0, labelFontSize=16, titleFontSize=14),
                sort=alt.EncodingSortField(field="avg_delay_min", order="descending")),
        y=alt.Y("avg_delay_min:Q",
                title="Average Delay (minutes)",
                axis=alt.Axis(labelFontSize=14, titleFontSize=14)),
        tooltip=["route_short_name", "avg_delay_min"]
    ).properties(height=500)

    st.altair_chart(chart, use_container_width=True)
    st.caption(f"{len(late_routes)} routes averaging more than 5 minutes late")
else:
    st.success("No routes averaging more than 5 minutes late!")

st.divider()
st.caption(f"Last updated: {data.get('generated_at', 'Unknown')[:16]} | Data from HSL GTFS-realtime API")
