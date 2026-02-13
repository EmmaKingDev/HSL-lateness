import json
import os
import boto3
from datetime import datetime

s3 = boto3.client("s3")
SILVER_BUCKET = os.environ["SILVER_BUCKET"]

def flatten_entities(decoded_feed):
    """Turn nested GTFS-RT into flat rows"""
    rows = []
    feed_timestamp = decoded_feed.get("header", {}).get("timestamp")

    for entity in decoded_feed.get("entity", []):
        trip_update = entity.get("trip_update")
        if not trip_update:
            continue

        trip = trip_update.get("trip", {})

        # Skip canceled trips — no stop predictions to flatten
        if trip.get("schedule_relationship") == "CANCELED":
            continue

        # Base fields from the trip level
        trip_info = {
            "feed_timestamp": feed_timestamp,
            "route_id": trip.get("route_id"),
            "start_time": trip.get("start_time"),
            "start_date": trip.get("start_date"),
            "direction_id": trip.get("direction_id"),
            "trip_id": entity.get("id"),
        }

        # One row per stop_time_update
        for stu in trip_update.get("stop_time_update", []):

            # Skip stops with no prediction data
            if stu.get("schedule_relationship") == "NO_DATA":
                continue

            row = {
                **trip_info,
                "stop_id": stu.get("stop_id"),
                "predicted_arrival": stu.get("arrival", {}).get("time"),
                "arrival_uncertainty": stu.get("arrival", {}).get("uncertainty"),
                "predicted_departure": stu.get("departure", {}).get("time"),
                "departure_uncertainty": stu.get("departure", {}).get("uncertainty"),
            }
            rows.append(row)

    return rows

def lambda_handler(event, context):
    # Step Functions passes these from Lambda A's output
    bronze_bucket = event["bronze_bucket"]
    bronze_key = event["bronze_key"]

    # Read the nested JSON from bronze
    response = s3.get_object(Bucket=bronze_bucket, Key=bronze_key)
    decoded_feed = json.loads(response["Body"].read())

    # Flatten
    rows = flatten_entities(decoded_feed)

    # Write to silver as newline-delimited JSON
    now = datetime.utcnow()
    silver_key = f"flat/year={now.year}/month={now.strftime('%m')}/day={now.strftime('%d')}/{now.strftime('%H%M%S')}.json"

    body = "\n".join(json.dumps(row) for row in rows)

    s3.put_object(
        Bucket=SILVER_BUCKET,
        Key=silver_key,
        Body=body,
        ContentType="application/json"
    )

    return {
        "status": "success",
        "silver_bucket": SILVER_BUCKET,
        "silver_key": silver_key,
        "row_count": len(rows),
        "timestamp": now.isoformat()
    }
