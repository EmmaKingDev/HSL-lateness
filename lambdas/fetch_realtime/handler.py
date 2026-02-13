import json
import os
import boto3
import requests
from datetime import datetime
from google.transit import gtfs_realtime_pb2
from google.protobuf.json_format import MessageToDict

s3 = boto3.client("s3")
BRONZE_BUCKET = os.environ["BRONZE_BUCKET"]
URL = "https://realtime.hsl.fi/realtime/trip-updates/v2/hsl"

def fetch_gtfs_realtime(url):
    response = requests.get(
        url,
        headers={"Accept": "application/x-protobuf"},
        timeout=30,
    )
    response.raise_for_status()
    return response.content

def decode_protobuf(binary_data):
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(binary_data)
    return MessageToDict(feed, preserving_proto_field_name=True)

def lambda_handler(event, context):
    now = datetime.utcnow()
    binary_data = fetch_gtfs_realtime(URL)
    decoded = decode_protobuf(binary_data)

    # S3 key with date partitioning
    s3_key = f"raw/year={now.year}/month={now.strftime('%m')}/day={now.strftime('%d')}/{now.strftime('%H%M%S')}.json"

    s3.put_object(
        Bucket=BRONZE_BUCKET,
        Key=s3_key,
        Body=json.dumps(decoded),
        ContentType="application/json"
    )

    return {
        "status": "success",
        "bronze_bucket": BRONZE_BUCKET,
        "bronze_key": s3_key,
        "entity_count": len(decoded.get("entity", [])),
        "timestamp": now.isoformat()
    }
