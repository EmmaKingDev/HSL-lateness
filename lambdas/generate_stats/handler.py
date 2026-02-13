"""
Generate daily stats JSON for public dashboard.
Queries Athena once and writes results to S3.
"""
import boto3
import json
import time
import os
from datetime import datetime, timedelta

REGION = "eu-north-1"
DATABASE = "hsl_transport"
WORKGROUP = "primary"
OUTPUT_BUCKET = os.environ.get("OUTPUT_BUCKET", "emkidev-results-hsl")
RESULTS_BUCKET = os.environ.get("RESULTS_BUCKET", "emkidev-results-hsl")


def run_athena_query(client, query: str) -> list[dict]:
    """Execute Athena query and return results as list of dicts."""
    response = client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": DATABASE},
        WorkGroup=WORKGROUP,
        ResultConfiguration={"OutputLocation": f"s3://{RESULTS_BUCKET}/"},
    )
    query_id = response["QueryExecutionId"]

    # Wait for completion
    while True:
        result = client.get_query_execution(QueryExecutionId=query_id)
        state = result["QueryExecution"]["Status"]["State"]
        if state == "SUCCEEDED":
            break
        elif state in ("FAILED", "CANCELLED"):
            raise Exception(f"Query {state}: {result['QueryExecution']['Status'].get('StateChangeReason')}")
        time.sleep(1)

    # Get results
    paginator = client.get_paginator("get_query_results")
    rows = []
    headers = None

    for page in paginator.paginate(QueryExecutionId=query_id):
        for i, row in enumerate(page["ResultSet"]["Rows"]):
            values = [col.get("VarCharValue", "") for col in row["Data"]]
            if headers is None:
                headers = values
            else:
                rows.append(dict(zip(headers, values)))

    return rows


def lambda_handler(event, context):
    """Generate stats JSON for public dashboard."""
    athena = boto3.client("athena", region_name=REGION)
    s3 = boto3.client("s3", region_name=REGION)

    # Use yesterday's date (full 24h of data) or today if specified
    target_date = datetime.now() - timedelta(days=1)
    year = target_date.strftime("%Y")
    month = target_date.strftime("%m")
    day = target_date.strftime("%d")

    # Query 1: Routes more than 5 minutes late
    routes_query = f"""
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

    # Query 2: Time range metadata
    meta_query = f"""
    SELECT
        MIN(from_unixtime(CAST(feed_timestamp AS bigint) + 7200)) as first_feed,
        MAX(from_unixtime(CAST(feed_timestamp AS bigint) + 7200)) as last_feed,
        COUNT(DISTINCT feed_timestamp) as feed_count
    FROM silver_realtime
    WHERE year = '{year}' AND month = '{month}' AND day = '{day}'
    """

    print(f"Generating stats for {year}-{month}-{day}")

    # Run queries
    routes = run_athena_query(athena, routes_query)
    meta = run_athena_query(athena, meta_query)

    # Build output
    output = {
        "generated_at": datetime.now().isoformat(),
        "date": f"{year}-{month}-{day}",
        "time_range": {
            "from": meta[0]["first_feed"][:16] if meta else None,  # YYYY-MM-DD HH:MM
            "to": meta[0]["last_feed"][:16] if meta else None,
            "feed_count": int(meta[0]["feed_count"]) if meta else 0,
        },
        "late_routes": [
            {
                "route": r["route_short_name"],
                "avg_delay_min": float(r["avg_delay_min"])
            }
            for r in routes
        ]
    }

    # Write to S3
    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key="public/latest.json",
        Body=json.dumps(output, indent=2),
        ContentType="application/json",
    )

    print(f"Wrote stats to s3://{OUTPUT_BUCKET}/public/latest.json")
    print(f"Found {len(routes)} routes >5min late")

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Stats generated",
            "late_routes_count": len(routes)
        })
    }
