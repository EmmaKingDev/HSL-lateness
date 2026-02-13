"""
GTFS Static Files → Parquet Converter

Converts trips.txt, stop_times.txt, stops.txt, and routes.txt to Parquet format
for use in Athena. Adds a derived start_time column to trips for joining with
realtime data.

Usage:
  1. Place your GTFS txt files in a folder
  2. Update INPUT_DIR and OUTPUT_DIR below
  3. Run: python convert_gtfs_to_parquet.py

The output Parquet files go to your S3 reference bucket.
"""

import pandas as pd
import os
import sys

INPUT_DIR = "./statics"      # folder with your .txt files
OUTPUT_DIR = "./output"    # folder for .parquet output


def convert_trips(input_dir, output_dir):
    """
    Convert trips.txt → trips.parquet

    Key transformation: extract start_time from trip_id
    Example: trip_id "1001_20260210_Ke_1_0540" → start_time "05:40:00"
    """
    print("\n--- trips.txt ---")
    df = pd.read_csv(os.path.join(input_dir, "trips.txt"))
    print(f"  Rows: {len(df):,}")
    print(f"  Columns: {list(df.columns)}")

    # Extract start time from trip_id
    # Pattern: routeid_date_daycode_direction_HHMM
    # We want the last segment
    def extract_start_time(trip_id):
        try:
            parts = trip_id.split("_")
            time_part = parts[-1]  # e.g., "0540"
            hours = time_part[:2]
            minutes = time_part[2:]
            return f"{hours}:{minutes}:00"
        except (IndexError, ValueError):
            return None

    df["start_time"] = df["trip_id"].apply(extract_start_time)

    # Show a few examples to verify
    print(f"\n  Start time extraction examples:")
    for _, row in df.head(3).iterrows():
        print(f"    {row['trip_id']} → {row['start_time']}")

    # Check for any failed extractions
    null_count = df["start_time"].isna().sum()
    if null_count > 0:
        print(f"  ⚠️  {null_count} rows failed start_time extraction")

    output_path = os.path.join(output_dir, "trips.parquet")
    df.to_parquet(output_path, index=False)
    print(f"  Saved → {output_path} ({os.path.getsize(output_path) / 1024 / 1024:.1f} MB)")
    return df


def convert_stop_times(input_dir, output_dir):
    """
    Convert stop_times.txt → stop_times.parquet

    This is the big one (753MB CSV). Parquet compression will shrink it
    dramatically because columnar storage handles repeated values well.
    """
    print("\n--- stop_times.txt ---")
    df = pd.read_csv(os.path.join(input_dir, "stop_times.txt"))
    print(f"  Rows: {len(df):,}")
    print(f"  Columns: {list(df.columns)}")

    # Show sample
    print(f"\n  Sample rows:")
    print(df.head(3).to_string(index=False))

    output_path = os.path.join(output_dir, "stop_times.parquet")
    df.to_parquet(output_path, index=False)

    original_size = os.path.getsize(os.path.join(input_dir, "stop_times.txt")) / 1024 / 1024
    parquet_size = os.path.getsize(output_path) / 1024 / 1024
    print(f"\n  CSV size:     {original_size:.1f} MB")
    print(f"  Parquet size: {parquet_size:.1f} MB")
    print(f"  Compression:  {(1 - parquet_size/original_size) * 100:.0f}% smaller")
    print(f"  Saved → {output_path}")
    return df


def convert_routes(input_dir, output_dir):
    """
    Convert routes.txt → routes.parquet

    Gives us: route_id → route_short_name (e.g., "3") + route_type (tram/bus/metro)
    """
    print("\n--- routes.txt ---")
    df = pd.read_csv(os.path.join(input_dir, "routes.txt"))
    print(f"  Rows: {len(df):,}")
    print(f"  Columns: {list(df.columns)}")

    # Show sample
    print(f"\n  Sample rows:")
    print(df.head(5).to_string(index=False))

    output_path = os.path.join(output_dir, "routes.parquet")
    df.to_parquet(output_path, index=False)
    print(f"  Saved → {output_path} ({os.path.getsize(output_path) / 1024:.1f} KB)")
    return df


def convert_stops(input_dir, output_dir):
    """
    Convert stops.txt → stops.parquet

    Gives us: stop_id → stop_name + lat/lon coordinates
    """
    print("\n--- stops.txt ---")
    df = pd.read_csv(os.path.join(input_dir, "stops.txt"))
    print(f"  Rows: {len(df):,}")
    print(f"  Columns: {list(df.columns)}")

    # Show sample
    print(f"\n  Sample rows:")
    print(df.head(5).to_string(index=False))

    output_path = os.path.join(output_dir, "stops.parquet")
    df.to_parquet(output_path, index=False)
    print(f"  Saved → {output_path} ({os.path.getsize(output_path) / 1024:.1f} KB)")
    return df


if __name__ == "__main__":
    print("=" * 60)
    print("GTFS Static → Parquet Converter")
    print("=" * 60)

    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Check input files exist
    required_files = ["trips.txt", "stop_times.txt", "routes.txt", "stops.txt"]
    missing = [f for f in required_files if not os.path.exists(os.path.join(INPUT_DIR, f))]
    if missing:
        print(f"\n❌ Missing files in {INPUT_DIR}: {missing}")
        print(f"   Place your GTFS files there and try again.")
        sys.exit(1)

    # Convert all files
    trips_df = convert_trips(INPUT_DIR, OUTPUT_DIR)
    stop_times_df = convert_stop_times(INPUT_DIR, OUTPUT_DIR)
    routes_df = convert_routes(INPUT_DIR, OUTPUT_DIR)
    stops_df = convert_stops(INPUT_DIR, OUTPUT_DIR)

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"""
  Files converted:
    trips.parquet      — {len(trips_df):,} rows (with derived start_time)
    stop_times.parquet — {len(stop_times_df):,} rows
    routes.parquet     — {len(routes_df):,} rows
    stops.parquet      — {len(stops_df):,} rows

  Next steps:
    1. Upload these to s3://emkidev-reference-hsl/
       aws s3 cp {OUTPUT_DIR}/ s3://emkidev-reference-hsl/ --recursive

    2. The Athena tables in athena.tf point at these files

    3. Test the join:
       SELECT s.route_id, s.predicted_arrival, st.arrival_time
       FROM silver_realtime s
       JOIN ref_trips t
           ON s.route_id = t.route_id
           AND s.direction_id = t.direction_id
           AND s.start_time = t.start_time
       JOIN ref_stop_times st
           ON t.trip_id = st.trip_id
           AND s.stop_id = st.stop_id
       LIMIT 10
""")
