"""Check what data we actually have in the pipeline."""
import boto3
import time

client = boto3.client("athena", region_name="eu-north-1")

query = """
SELECT
    year, month, day,
    MIN(feed_timestamp) as earliest_feed,
    MAX(feed_timestamp) as latest_feed,
    COUNT(*) as row_count,
    COUNT(DISTINCT feed_timestamp) as unique_feeds
FROM hsl_transport.silver_realtime
GROUP BY year, month, day
ORDER BY year, month, day
"""

response = client.start_query_execution(
    QueryString=query,
    QueryExecutionContext={"Database": "hsl_transport"},
    WorkGroup="primary",
    ResultConfiguration={"OutputLocation": "s3://emkidev-results-hsl/"},
)

query_id = response["QueryExecutionId"]
print(f"Query ID: {query_id}")

while True:
    result = client.get_query_execution(QueryExecutionId=query_id)
    state = result["QueryExecution"]["Status"]["State"]
    print(f"Status: {state}")
    if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
        break
    time.sleep(1)

if state == "SUCCEEDED":
    results = client.get_query_results(QueryExecutionId=query_id)
    print("\n" + "="*80)
    print("DATA AVAILABLE IN SILVER LAYER:")
    print("="*80)
    for row in results["ResultSet"]["Rows"]:
        print(" | ".join([col.get("VarCharValue", "") for col in row["Data"]]))
