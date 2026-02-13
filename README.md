# HSL Public Transport Performance Monitor

A serverless data pipeline that collects Helsinki public transport realtime predictions and calculates delay metrics using the **medallion architecture** (Bronze → Silver → Gold).

## Architecture

```
HSL Realtime API                    GTFS Static Files
(Protobuf)                          (Weekly update)
    │                                      │
    v                                      v
┌──────────────────┐               ┌──────────────────┐
│  BRONZE BUCKET   │               │  REFERENCE       │
│  (Raw JSON)      │               │  BUCKET          │
│                  │               │  (Parquet)       │
└────────┬─────────┘               └────────┬─────────┘
         │                                  │
         v                                  │
┌──────────────────┐                        │
│  SILVER BUCKET   │                        │
│  (Flat NDJSON)   │                        │
└────────┬─────────┘                        │
         │                                  │
         └──────────────┬───────────────────┘
                        │
                        v
               ┌──────────────────┐
               │  GOLD LAYER      │
               │  (Athena VIEW)   │  ← Virtual, no storage
               │                  │
               │  Joins + delay   │
               │  calculation     │
               └────────┬─────────┘
                        │
                        v
               ┌──────────────────┐
               │  ATHENA          │
               │  (SQL Queries)   │
               └────────┬─────────┘
                        │
                        v
               ┌──────────────────┐
               │  QUICKSIGHT      │
               │  (Dashboards)    │
               └──────────────────┘
```

**Key Design Decision:** The Gold layer is an Athena VIEW, not a physical table. This "semantic layer" pattern handles 18M+ row joins that Lambda couldn't, eliminates storage costs, and ensures data is always fresh.

For a detailed walkthrough of the data transformations, see [DATA_PIPELINE.md](DATA_PIPELINE.md).

## Quick Start

### Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.0
- Python 3.12

### 1. Initialize Terraform

```bash
cd terraform
terraform init
terraform apply
```

### 2. Upload Reference Data

Convert GTFS static files to Parquet and upload:

```bash
# Convert (requires pandas, pyarrow)
python convertToParquet.py

# Upload to S3
aws s3 cp output/trips.parquet s3://emkidev-reference-hsl/trips/trips.parquet
aws s3 cp output/stop_times.parquet s3://emkidev-reference-hsl/stop_times/stop_times.parquet
aws s3 cp output/routes.parquet s3://emkidev-reference-hsl/routes/routes.parquet
aws s3 cp output/stops.parquet s3://emkidev-reference-hsl/stops/stops.parquet
```

### 3. Create Gold View

Run the named query in Athena Console:
1. Go to Athena → Saved queries
2. Find `create-gold-performance-view`
3. Run the query

Or via CLI:
```bash
aws athena start-query-execution \
  --query-string "$(aws athena get-named-query --named-query-id <ID> --query 'NamedQuery.QueryString' --output text)" \
  --work-group primary \
  --query-execution-context Database=hsl_transport
```

### 4. Enable the Pipeline

```bash
# Enable EventBridge schedule (runs every 15 minutes)
aws events enable-rule --name hsl-pipeline-trigger
```

### 5. Register Partitions

After data arrives, register partitions for querying:

```sql
MSCK REPAIR TABLE silver_realtime;
```

## Project Structure

```
infra-hsl/
├── terraform/
│   ├── main.tf           # Provider, backend config
│   ├── s3.tf             # Bronze, silver, gold, reference, results buckets
│   ├── lambda.tf         # fetch_realtime, flatten_data Lambdas
│   ├── iam.tf            # IAM roles and policies
│   ├── stepfunctions.tf  # Pipeline orchestration
│   ├── eventbridge.tf    # 15-minute schedule trigger
│   └── athena.tf         # Glue tables + gold_performance VIEW
├── lambdas/
│   ├── fetch_realtime/   # Protobuf → Bronze JSON
│   └── flatten_data/     # Nested → Flat NDJSON
├── layers/
│   └── lambda_layer.zip  # Dependencies (gtfs-realtime-bindings, pyarrow)
├── statics/              # GTFS static files (trips.txt, stops.txt, etc.)
├── output/               # Converted Parquet files
├── DATA_PIPELINE.md      # Detailed data transformation documentation
└── README.md
```

## S3 Buckets

| Bucket | Purpose | Format |
|--------|---------|--------|
| `emkidev-bronze-hsl` | Raw API responses | JSON (nested) |
| `emkidev-silver-hsl` | Flattened predictions | NDJSON (partitioned) |
| `emkidev-gold-hsl` | (Unused - Gold is a VIEW) | - |
| `emkidev-reference-hsl` | Static GTFS lookup tables | Parquet |
| `emkidev-athena-results-hsl` | Query results | CSV |

## Athena Tables

| Table | Type | Rows | Description |
|-------|------|------|-------------|
| `silver_realtime` | External | ~10K/file | Flattened realtime predictions |
| `ref_trips` | External | 175K | Trip metadata |
| `ref_stop_times` | External | 18M | Scheduled arrival times |
| `ref_routes` | External | 2.5K | Route names |
| `ref_stops` | External | 8.5K | Stop names & locations |
| `gold_performance` | **VIEW** | - | Enriched with delay calculation |

## Example Queries

### Average Delay by Route

```sql
SELECT
    route_short_name,
    ROUND(AVG(delay_seconds), 0) as avg_delay_sec,
    COUNT(*) as predictions
FROM hsl_transport.gold_performance
WHERE year = '2026' AND month = '02'
  AND scheduled_arrival IS NOT NULL
GROUP BY route_short_name
ORDER BY avg_delay_sec DESC
LIMIT 20;
```

### Worst Performing Stops

```sql
SELECT
    stop_name,
    route_short_name,
    ROUND(AVG(delay_seconds), 0) as avg_delay,
    MAX(delay_seconds) as max_delay
FROM hsl_transport.gold_performance
WHERE year = '2026' AND month = '02' AND day = '13'
  AND scheduled_arrival IS NOT NULL
GROUP BY stop_name, route_short_name
HAVING AVG(delay_seconds) > 120
ORDER BY avg_delay DESC
LIMIT 20;
```

### Delay Distribution

```sql
SELECT
    CASE
        WHEN delay_seconds < -300 THEN 'Early (>5min)'
        WHEN delay_seconds < -60 THEN 'Early (1-5min)'
        WHEN delay_seconds < 60 THEN 'On time'
        WHEN delay_seconds < 300 THEN 'Late (1-5min)'
        ELSE 'Late (>5min)'
    END as status,
    COUNT(*) as count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as pct
FROM hsl_transport.gold_performance
WHERE year = '2026' AND month = '02'
  AND scheduled_arrival IS NOT NULL
GROUP BY 1
ORDER BY 2 DESC;
```

## Visualization with QuickSight

Amazon QuickSight provides serverless dashboards that connect directly to Athena.

### Pricing

- **30-day free trial** (4 users) - perfect for screenshots/demo
- After trial: $9/month per author (prorated, cancel anytime)
- No charge if you delete before trial ends

### Setup Steps

#### 1. Sign Up for QuickSight

```
AWS Console → QuickSight → Sign up for QuickSight
  → Choose "Standard" edition
  → Select your region (eu-north-1)
```

#### 2. Grant Data Access

During setup, allow QuickSight access to:
- **Athena**: Enable Athena workgroup access
- **S3 buckets**: Select these buckets:
  - `emkidev-silver-hsl`
  - `emkidev-reference-hsl`
  - `emkidev-athena-results-hsl`

#### 3. Create Dataset

```
QuickSight → Datasets → New dataset → Athena
  → Data source name: "hsl-performance"
  → Workgroup: primary
  → Database: hsl_transport
  → Tables: gold_performance (the VIEW)
  → Select "Import to SPICE for quicker analytics"
  → Visualize
```

#### 4. Build Dashboards

| Visualization | Chart Type | X-Axis | Value |
|---------------|------------|--------|-------|
| Delay by route | Horizontal bar | route_short_name | AVG(delay_seconds) |
| Delay trend | Line chart | feed_timestamp | AVG(delay_seconds) |
| On-time % | Donut chart | delay_bucket* | COUNT |
| Worst stops | Table | stop_name | AVG(delay_seconds) |

*Create calculated field for delay_bucket:
```
ifelse(
  delay_seconds < -60, 'Early',
  delay_seconds < 60, 'On Time',
  delay_seconds < 300, 'Late (<5min)',
  'Late (>5min)'
)
```

#### 5. Teardown

```
QuickSight → Manage QuickSight → Account settings → Delete account
```

This removes all QuickSight resources and stops billing.

## Cost Estimate (Monthly)

| Service | Usage | Cost |
|---------|-------|------|
| Lambda | ~8,640 invocations | ~$0.02 |
| S3 | ~1.2 GB storage | ~$0.03 |
| Step Functions | ~8,640 transitions | ~$0.22 |
| Athena | ~10 GB scanned | ~$0.50 |
| QuickSight | 1 author | Free trial / $9 |
| **Total** | | **~$0.80/month** (pipeline only) |

## Limitations

- **Unmatched records**: Some realtime trips don't match static GTFS (special services). These have `NULL` scheduled_arrival.
- **Overnight trips**: Trips crossing midnight may have incorrect delay calculations.
- **Reference data freshness**: GTFS static data is updated weekly; upload new Parquet files when HSL releases updates.

## Data Sources

- **Realtime**: [HSL GTFS-realtime API](https://digitransit.fi/en/developers/apis/4-realtime-api/)
- **Static**: [HSL GTFS Static Feed](https://www.hsl.fi/hsl/avoin-data)

## License

MIT
