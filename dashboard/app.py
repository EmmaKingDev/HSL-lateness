"""
HSL Performance Dashboard - Which lines are late today?
Run with: streamlit run app.py

Reads stats from bundled JSON file (frozen mode) or S3 (live mode).
"""
import streamlit as st
import pandas as pd
import altair as alt
import json
from pathlib import Path

st.set_page_config(page_title="HSL Late Lines", layout="wide", menu_items={})

# Hide deploy button and menu
st.markdown(
    """
    <style>
        .stDeployButton {display: none;}
        #MainMenu {visibility: hidden;}
    </style>
    """,
    unsafe_allow_html=True,
)

st.title("Which HSL lines are late?")

# Load stats from bundled JSON file
data_path = Path(__file__).parent / "data" / "latest.json"
try:
    with open(data_path) as f:
        data = json.load(f)
except FileNotFoundError:
    st.error("Stats file not found.")
    st.stop()

# Show frozen banner if service is paused
if data.get("frozen"):
    st.warning(data.get("frozen_message", "This service is paused. Showing historic data."))

# Display metadata
date = data.get("date", "Unknown")
time_range = data.get("time_range", {})
time_from = time_range.get("from", "")[-5:] if time_range.get("from") else ""
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
st.caption(f"Data collected: {data.get('generated_at', 'Unknown')[:16]} | Source: HSL GTFS-realtime API")
