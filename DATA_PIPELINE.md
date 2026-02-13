# HSL Data Pipeline: From Binary to Insights

This document traces a single data point through the entire medallion architecture,
showing exactly how raw protobuf bytes transform into analytics-ready delay metrics.

---

## Pipeline Overview

```
                              GTFS Static Files
                                      |
                                      v
                            +------------------+
                            |   REFERENCE      |
                            |   BUCKET         |
                            |   (Parquet)      |
                            +--------+---------+
                                     |
    +------------------+             |
    |  HSL Realtime    |             |
    |  Protobuf API    |             |
    +--------+---------+             |
             |                       |
             v                       |
    +------------------+             |
    |  BRONZE BUCKET   |             |
    |  (Raw JSON)      |             |
    |  Lambda: fetch   |             |
    +--------+---------+             |
             |                       |
             v                       |
    +------------------+             |
    |  SILVER BUCKET   |             |
    |  (Flat NDJSON)   |             |
    |  Lambda: flatten |             |
    +--------+---------+             |
             |                       |
             +-----------+-----------+
                         |
                         v
                +------------------+
                |  GOLD LAYER      |
                |  (Athena VIEW)   |  <-- Virtual, no storage
                |                  |
                |  Joins silver +  |
                |  reference data  |
                |  on-demand       |
                +--------+---------+
                         |
                         v
                +------------------+
                |  ATHENA          |
                |  (SQL Queries)   |
                +------------------+
```

## Key Architecture Decision: Gold as a VIEW

The Gold layer is implemented as an **Athena VIEW**, not a physical table or Lambda.
This "semantic layer" pattern was chosen after discovering that Lambda-based enrichment
couldn't handle the 18M+ row joins required:

| Approach | Memory | Timeout | Scalability |
|----------|--------|---------|-------------|
| Lambda (original) | 3GB limit | 5min limit | Failed |
| **Athena VIEW** | Unlimited | Unlimited | Works |

**Benefits:**
- Computes enriched data on-demand (always fresh)
- No data duplication (saves storage cost)
- No ETL pipeline step needed
- Handles joins across 18M reference records
- Timezone conversion built into the view (UTC → Helsinki +2h)

---

## Stage 0: Raw Input (Protobuf Binary)

**Source:** `https://realtime.hsl.fi/realtime/trip-updates/v2/hsl`

The HSL API returns GTFS-realtime data encoded as Protocol Buffers (protobuf),
a compact binary serialization format.

```
Raw bytes (hex excerpt):
0a 0f 31 30 30 31 5f 32 30 32 36 30 32 31 33 5f
4b 65 5f 31 5f 30 35 34 30 12 08 08 01 10 00 18
...
```

**Size:** ~50-200 KB per request (compressed binary)

**Why protobuf?**
- 3-10x smaller than JSON
- Faster to parse
- Schema-enforced structure

---

## Stage 1: Bronze Layer (Decoded JSON)

**Lambda:** `hsl-fetch-realtime`
**Output:** `s3://emkidev-bronze-hsl/raw/year=2026/month=02/day=13/120000.json`

The fetch Lambda decodes the protobuf into nested JSON, preserving the
original GTFS-realtime structure.

```
+------------------------------------------------------------------+
|                        BRONZE: Nested JSON                        |
+------------------------------------------------------------------+

{
  "header": {
    "gtfs_realtime_version": "2.0",
    "timestamp": 1770825600              <-- Feed generation time
  },
  "entity": [
    {
      "id": "1001_20260213_Ke_1_0540",
      "trip_update": {
        "trip": {
          "route_id": "1001",            <-- Tram line 1
          "start_time": "05:40:00",      <-- Scheduled departure
          "start_date": "20260213",
          "direction_id": 0,             <-- Outbound
          "schedule_relationship": "SCHEDULED"
        },
        "stop_time_update": [
          {
            "stop_id": "1050417",        <-- Käpylä station
            "arrival": {
              "time": 1770826200,        <-- Unix timestamp (UTC)
              "uncertainty": 30
            },
            "departure": {
              "time": 1770826260,
              "uncertainty": 30
            },
            "schedule_relationship": "SCHEDULED"
          },
          ...                            <-- More stops
        ]
      }
    },
    ...                                  <-- 500+ more entities
  ]
}
```

**Transformation Applied:**
```
Protobuf Binary  -->  gtfs-realtime-bindings  -->  JSON
   (bytes)              (Python library)         (nested)
```

**Key Characteristics:**
- Deeply nested structure (3-4 levels)
- One entity per active trip
- Each entity contains 10-50 stop predictions
- ~500-2000 entities per feed

---

## Stage 2: Silver Layer (Flattened NDJSON)

**Lambda:** `hsl-flatten-data`
**Output:** `s3://emkidev-silver-hsl/flat/year=2026/month=02/day=13/120000.json`

The flatten Lambda explodes the nested structure into one row per stop prediction,
creating a tabular format suitable for SQL queries.

```
+------------------------------------------------------------------+
|                     SILVER: Flat NDJSON                           |
|                   (one JSON object per line)                      |
+------------------------------------------------------------------+

{"feed_timestamp":"1770825600","route_id":"1001","start_time":"05:40:00",...}
{"feed_timestamp":"1770825600","route_id":"1001","start_time":"05:40:00",...}
{"feed_timestamp":"1770825600","route_id":"1001","start_time":"05:40:00",...}
...
```

**Transformation Applied:**
```
                    +-- stop_time_update[0] --> Row 1
                    |
Bronze Entity  -----+-- stop_time_update[1] --> Row 2
                    |
                    +-- stop_time_update[2] --> Row 3
```

**Data Explosion:**
```
1 Bronze file (~500 trips x ~20 stops each) = ~10,000 Silver rows
```

**Filtering Applied:**
- Skip `CANCELED` trips
- Skip `NO_DATA` stops
- Skip stops with null predictions

**Silver Schema:**

| Column | Type | Example | Description |
|--------|------|---------|-------------|
| feed_timestamp | string | "1770825600" | When HSL generated this feed |
| route_id | string | "1001" | Internal route identifier |
| start_time | string | "05:40:00" | Scheduled trip start |
| start_date | string | "20260213" | Service date (YYYYMMDD) |
| direction_id | int | 0 | 0=outbound, 1=inbound |
| trip_id | string | "1001_20260213..." | Unique trip identifier |
| stop_id | string | "1050417" | Stop/station identifier |
| predicted_arrival | string | "1770826200" | Unix timestamp (UTC) |
| arrival_uncertainty | int | 30 | Uncertainty in seconds |
| predicted_departure | string | "1770826260" | Unix timestamp (UTC) |
| departure_uncertainty | int | 30 | Uncertainty in seconds |

---

## Reference Data (Static GTFS)

**Source:** HSL GTFS static feed (updated weekly)
**Storage:** `s3://emkidev-reference-hsl/` (Parquet format)

```
+------------------------------------------------------------------+
|                    REFERENCE: Lookup Tables                       |
+------------------------------------------------------------------+

TRIPS (175,000 rows)
+----------+-------------+-----------+--------------------+
| route_id | direction_id| start_time| trip_id            |
+----------+-------------+-----------+--------------------+
| 1001     | 0           | 05:40:00  | 1001_20260213_Ke.. |
| 1001     | 0           | 05:55:00  | 1001_20260213_Ke.. |
+----------+-------------+-----------+--------------------+
        |
        |  JOIN KEY: (route_id, direction_id, start_time)
        v

STOP_TIMES (18,000,000 rows)
+--------------------+---------+--------------+---------------+
| trip_id            | stop_id | arrival_time | stop_sequence |
+--------------------+---------+--------------+---------------+
| 1001_20260213_Ke.. | 1050417 | 05:40:00     | 1             |
| 1001_20260213_Ke.. | 1050419 | 05:42:00     | 2             |
+--------------------+---------+--------------+---------------+
              |
              | JOIN KEY: (trip_id, stop_id)
              v
        SCHEDULED ARRIVAL TIME


ROUTES (2,500 rows)                    STOPS (8,500 rows)
+----------+------------------+        +---------+------------------+
| route_id | route_short_name |        | stop_id | stop_name        |
+----------+------------------+        +---------+------------------+
| 1001     | 1                |        | 1050417 | Käpylä           |
| 1003     | 2                |        | 1050419 | Koskelantie      |
+----------+------------------+        +---------+------------------+
     ^                                      ^
     |                                      |
  LOOKUP                                 LOOKUP
```

---

## Stage 3: Gold Layer (Athena VIEW)

**Implementation:** Athena VIEW `gold_performance`
**Storage:** None (virtual layer, computed on-demand)

The gold layer is a SQL VIEW that joins silver realtime data with all four
reference tables and computes the delay metric.

```sql
CREATE VIEW gold_performance AS
SELECT
    s.feed_timestamp,
    s.route_id,
    r.route_short_name,
    s.trip_id,
    s.direction_id,
    s.stop_id,
    st.stop_name,
    stm.stop_sequence,
    stm.arrival_time as scheduled_arrival,
    -- Convert Unix timestamp to Helsinki time (UTC+2)
    date_format(from_unixtime(predicted_arrival + 7200), '%H:%i:%s') as predicted_arrival,
    -- Calculate delay in seconds
    (predicted_seconds) - (scheduled_seconds) as delay_seconds,
    s.arrival_uncertainty,
    s.year, s.month, s.day
FROM silver_realtime s
LEFT JOIN ref_trips t ON (route_id, direction_id, start_time)
LEFT JOIN ref_stop_times stm ON (trip_id, stop_id)
LEFT JOIN ref_routes r ON (route_id)
LEFT JOIN ref_stops st ON (stop_id)
```

**Join Pipeline:**
```
Silver Row
    |
    +-- (route_id, direction_id, start_time) --> ref_trips --> trip_id
    |                                                              |
    +-- (trip_id, stop_id) --> ref_stop_times --> scheduled_arrival
    |
    +-- route_id --> ref_routes --> route_short_name
    |
    +-- stop_id --> ref_stops --> stop_name
    |
    v
Gold Row (enriched with names + delay calculation)
```

**Timezone Handling:**
```
Unix timestamp (UTC):     1770826200
+ Helsinki offset:        + 7200 seconds (2 hours)
= Helsinki timestamp:     1770833400
= Time string:            "07:43:20"
```

**Delay Calculation:**
```
predicted (Helsinki):  "07:43:20"  -->  27800 seconds since midnight
scheduled:             "07:40:00"  -->  27600 seconds since midnight
                                        ------
delay_seconds:                           200 seconds (3 min 20 sec late)
```

**Gold Schema:**

| Column | Type | Example | Description |
|--------|------|---------|-------------|
| feed_timestamp | string | "1770825600" | Feed generation time |
| route_id | string | "1001" | Internal route ID |
| route_short_name | string | "1" | Public route number |
| trip_id | string | "1001_20260213..." | Unique trip ID |
| direction_id | int | 0 | Travel direction |
| stop_id | string | "1050417" | Stop identifier |
| stop_name | string | "Käpylä" | Human-readable stop name |
| stop_sequence | int | 1 | Position in trip |
| scheduled_arrival | string | "07:40:00" | From static GTFS |
| predicted_arrival | string | "07:43:20" | Realtime (Helsinki time) |
| delay_seconds | int | 200 | Positive=late, negative=early |
| arrival_uncertainty | int | 30 | Prediction confidence |

---

## Data Volume Summary

```
                    BRONZE              SILVER              GOLD (VIEW)
                    ------              ------              -----------
Files/day:          96                  96                  N/A
                    (every 15 min)

Rows/file:          ~500 trips          ~10,000 rows        Computed
                    (nested)            (flat)              on-demand

File size:          50-200 KB           200-500 KB          No storage

Daily volume:       ~10 MB              ~30 MB              0 MB

Monthly volume:     ~300 MB             ~900 MB             0 MB
```

---

## Query Examples (Athena)

**Average delay by route:**
```sql
SELECT
    route_short_name,
    AVG(delay_seconds) as avg_delay_sec,
    COUNT(*) as predictions
FROM gold_performance
WHERE year = '2026' AND month = '02'
  AND scheduled_arrival IS NOT NULL
GROUP BY route_short_name
ORDER BY avg_delay_sec DESC;
```

**Worst performing stops:**
```sql
SELECT
    stop_name,
    route_short_name,
    AVG(delay_seconds) as avg_delay,
    MAX(delay_seconds) as max_delay
FROM gold_performance
WHERE year = '2026' AND month = '02' AND day = '13'
  AND scheduled_arrival IS NOT NULL
GROUP BY stop_name, route_short_name
HAVING AVG(delay_seconds) > 120
ORDER BY avg_delay DESC
LIMIT 20;
```

**Delay distribution:**
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
FROM gold_performance
WHERE year = '2026' AND month = '02'
  AND scheduled_arrival IS NOT NULL
GROUP BY 1
ORDER BY 2 DESC;
```

---

## Architecture Benefits

| Layer | Purpose | Storage | Query Pattern |
|-------|---------|---------|---------------|
| **Bronze** | Archive, reprocessing | Physical | "What did the raw feed look like?" |
| **Silver** | Debugging, data quality | Physical | "What predictions were made?" |
| **Gold** | Analytics, dashboards | Virtual (VIEW) | "How delayed was route X?" |
| **Reference** | Lookups, joins | Physical (Parquet) | "What's the name for ID X?" |

**Why This Architecture?**

1. **Replayability** - Can reprocess silver from bronze if logic changes
2. **Debugging** - Each layer is independently queryable
3. **Scalability** - Athena VIEW handles 18M+ row joins that Lambda couldn't
4. **Cost** - No storage for gold layer; pay only for queries
5. **Freshness** - Gold data is always current (computed on-demand)
