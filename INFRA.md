# HSL Public Transport Performance Monitor — Architecture Overview

## Infrastructure (Terraform)

```
terraform/
├── provider.tf        — AWS eu-north-1 (Stockholm, closest to Helsinki)
├── variables.tf       — Shared variables
├── outputs.tf         — Export values (ARNs, bucket names)
├── s3.tf              — 5 buckets
├── iam.tf             — Roles + policies for all services
├── lambda.tf          — 2 Lambda functions + layer
├── stepfunctions.tf   — Pipeline state machine
├── eventbridge.tf     — 15-minute schedule trigger
└── athena.tf          — Glue catalog database + tables

lambdas/
├── fetch_realtime/
│   └── handler.py     — Fetches protobuf, decodes, writes to S3
└── flatten_data/
    └── handler.py     — Reads nested JSON, outputs flat NDJSON

layers/
└── dependencies/      — gtfs-realtime-bindings, requests, protobuf
```

## Data Flow

```
Every 15 minutes:

EventBridge (clock)
    │
    ▼
Step Functions (orchestrator)
    │
    ├──→ Lambda A: fetch_realtime
    │       │
    │       │  1. GET https://realtime.hsl.fi/realtime/trip-updates/v2/hsl
    │       │  2. Decode protobuf → JSON
    │       │  3. Write to S3 bronze
    │       │
    │       ▼
    │    S3: emkidev-bronze-hsl
    │       raw/year=2026/month=02/day=11/071500.json
    │       (nested: feed → entity → trip_update → stop_time_update[])
    │
    ├──→ Lambda B: flatten_data
    │       │
    │       │  1. Read nested JSON from bronze
    │       │  2. Skip CANCELED trips, NO_DATA stops
    │       │  3. Flatten to one row per stop prediction
    │       │  4. Write NDJSON to S3 silver
    │       │
    │       ▼
    │    S3: emkidev-silver-hsl
    │       flat/year=2026/month=02/day=11/071500.json
    │       (flat: one JSON object per line, all same columns)
    │
    ├──→ Success ✓
    │
    └──→ Failure ✗ (after retries: 3 for fetch, 2 for flatten)
              → CloudWatch alarm (future)
```

## S3 Buckets (5)

```
emkidev-bronze-hsl       Raw decoded protobuf dumps (archive/reprocessing)
emkidev-silver-hsl       Flat NDJSON rows (Athena queryable)
emkidev-gold-hsl         Aggregated summaries (future: dashboard reads from here)
emkidev-reference-hsl    Static GTFS files as Parquet (routes, stops, stop_times)
emkidev-results-hsl      Athena query output
```

## Athena Query Layer

```
┌─────────────────────────────────────────────────────────┐
│  Athena (serverless SQL engine)                         │
│                                                         │
│  Database: hsl_transport                                │
│                                                         │
│  Tables:                                                │
│    silver_realtime  → s3://emkidev-silver-hsl/flat/     │
│    ref_stop_times   → s3://emkidev-reference-hsl/...    │
│    ref_routes       → s3://emkidev-reference-hsl/...    │
│    ref_stops        → s3://emkidev-reference-hsl/...    │
│                                                         │
│  Example query:                                         │
│  SELECT                                                 │
│    s.route_id,                                          │
│    s.stop_id,                                           │
│    s.predicted_arrival,                                 │
│    st.arrival_time AS scheduled_arrival                 │
│   FROM silver_realtime s                                │
│   JOIN ref_trips t                                      │
│    ON s.route_id = t.route_id                           │
│    AND s.direction_id = t.direction_id                  │
│    AND s.start_time = -- matched to trip start time     │
│   JOIN ref_stop_times st                                │          
│    ON t.trip_id = st.trip_id                            │
│    AND s.stop_id = st.stop_id                           │
│                                                         │
│  Results → s3://emkidev-results-hsl/                    │
└─────────────────────────────────────────────────────────┘
```

## IAM Roles (5)

```
hsl-lambda-fetch-role       S3 PutObject (bronze) + CloudWatch Logs
hsl-lambda-flatten-role     S3 GetObject (bronze) + PutObject (silver) + CloudWatch Logs
hsl-stepfunctions-role      Lambda InvokeFunction (both lambdas)
hsl-eventbridge-role        States StartExecution (step functions)
hsl-athena-query-role       Athena + Glue + S3 read (silver, reference) + S3 write (results)
```

## Silver Row Schema

```json
{
  "feed_timestamp":       "1770790015",
  "route_id":             "1003",
  "start_time":           "07:43:00",
  "start_date":           "20260211",
  "direction_id":         0,
  "trip_id":              "7990511892324255",
  "stop_id":              "1090415",
  "predicted_arrival":    "1770788202",
  "arrival_uncertainty":  0,
  "predicted_departure":  "1770788601",
  "departure_uncertainty": 0
}
```

## Cost Estimate (MVP)

```
S3 storage:     ~$0.07/month (1MB × 96 snapshots/day × 30 days)
Lambda:         Free tier covers ~1M requests/month (you use ~6,000)
Step Functions: Free tier covers 4,000 transitions/month (you use ~8,640)
                Slightly over free tier: ~$0.02/month
Athena:         $5/TB scanned, at your volumes: ~$0.01/query
EventBridge:    Free for scheduled rules
─────────────────────────────────────────────
Total:          < $1/month
```

## What's Built vs What's Next

```
✅ BUILT (MVP infrastructure):
   - S3 buckets (bronze, silver, gold, reference, results)
   - IAM roles and policies for all services
   - Lambda functions (fetch + flatten)
   - Step Functions orchestration with retry logic
   - EventBridge 15-minute schedule
   - Athena table definitions (silver_realtime)

⬜ NEXT STEPS:
   - Convert stop_times.txt → Parquet, upload to reference bucket
   - Athena reference tables (routes, stops, stop_times)
   - Test the pipeline end-to-end
   - CloudWatch alarms for pipeline failures
   - Weather enrichment (FMI API → Lambda C)
   - Gold aggregation layer
   - Static dashboard (S3 + CloudFront)
```
