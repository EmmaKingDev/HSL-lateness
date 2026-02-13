resource "aws_glue_catalog_database" "hsl" {
  name = "hsl_transport"
}

# =============================================================================
# REFERENCE TABLES (Parquet SerDe)
# =============================================================================

resource "aws_glue_catalog_table" "ref_trips" {
  database_name = aws_glue_catalog_database.hsl.name
  name          = "ref_trips"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "parquet"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_bucket[3].id}/trips/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "route_id"
      type = "string"
    }
    columns {
      name = "service_id"
      type = "string"
    }
    columns {
      name = "trip_id"
      type = "string"
    }
    columns {
      name = "trip_headsign"
      type = "string"
    }
    columns {
      name = "direction_id"
      type = "bigint"
    }
    columns {
      name = "shape_id"
      type = "string"
    }
    columns {
      name = "wheelchair_accessible"
      type = "bigint"
    }
    columns {
      name = "bikes_allowed"
      type = "bigint"
    }
    columns {
      name = "max_delay"
      type = "bigint"
    }
    columns {
      name = "start_time"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "ref_stop_times" {
  database_name = aws_glue_catalog_database.hsl.name
  name          = "ref_stop_times"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "parquet"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_bucket[3].id}/stop_times/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "trip_id"
      type = "string"
    }
    columns {
      name = "arrival_time"
      type = "string"
    }
    columns {
      name = "departure_time"
      type = "string"
    }
    columns {
      name = "stop_id"
      type = "bigint"
    }
    columns {
      name = "stop_sequence"
      type = "bigint"
    }
    columns {
      name = "stop_headsign"
      type = "string"
    }
    columns {
      name = "pickup_type"
      type = "bigint"
    }
    columns {
      name = "drop_off_type"
      type = "bigint"
    }
    columns {
      name = "shape_dist_traveled"
      type = "double"
    }
    columns {
      name = "timepoint"
      type = "bigint"
    }
  }
}

resource "aws_glue_catalog_table" "ref_routes" {
  database_name = aws_glue_catalog_database.hsl.name
  name          = "ref_routes"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "parquet"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_bucket[3].id}/routes/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "route_id"
      type = "string"
    }
    columns {
      name = "agency_id"
      type = "string"
    }
    columns {
      name = "route_short_name"
      type = "string"
    }
    columns {
      name = "route_long_name"
      type = "string"
    }
    columns {
      name = "route_desc"
      type = "string"
    }
    columns {
      name = "route_type"
      type = "bigint"
    }
    columns {
      name = "route_url"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "ref_stops" {
  database_name = aws_glue_catalog_database.hsl.name
  name          = "ref_stops"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "parquet"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_bucket[3].id}/stops/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "stop_id"
      type = "bigint"
    }
    columns {
      name = "stop_code"
      type = "string"
    }
    columns {
      name = "stop_name"
      type = "string"
    }
    columns {
      name = "stop_desc"
      type = "string"
    }
    columns {
      name = "stop_lat"
      type = "double"
    }
    columns {
      name = "stop_lon"
      type = "double"
    }
    columns {
      name = "zone_id"
      type = "string"
    }
    columns {
      name = "stop_url"
      type = "string"
    }
    columns {
      name = "location_type"
      type = "bigint"
    }
    columns {
      name = "parent_station"
      type = "string"
    }
    columns {
      name = "wheelchair_boarding"
      type = "bigint"
    }
    columns {
      name = "platform_code"
      type = "string"
    }
    columns {
      name = "vehicle_type"
      type = "bigint"
    }
    columns {
      name = "radius"
      type = "bigint"
    }
  }
}

# =============================================================================
# SILVER TABLE (JSON SerDe - realtime predictions)
# =============================================================================

resource "aws_glue_catalog_table" "silver_realtime" {
  database_name = aws_glue_catalog_database.hsl.name
  name          = "silver_realtime"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "json"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_bucket[1].id}/flat/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "feed_timestamp"
      type = "string"
    }
    columns {
      name = "route_id"
      type = "string"
    }
    columns {
      name = "start_time"
      type = "string"
    }
    columns {
      name = "start_date"
      type = "string"
    }
    columns {
      name = "direction_id"
      type = "int"
    }
    columns {
      name = "trip_id"
      type = "string"
    }
    columns {
      name = "stop_id"
      type = "string"
    }
    columns {
      name = "predicted_arrival"
      type = "string"
    }
    columns {
      name = "arrival_uncertainty"
      type = "int"
    }
    columns {
      name = "predicted_departure"
      type = "string"
    }
    columns {
      name = "departure_uncertainty"
      type = "int"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
}

# =============================================================================
# GOLD LAYER (Athena View - virtual semantic layer)
# =============================================================================
#
# The gold layer is implemented as a VIEW that joins silver realtime data
# with reference tables on-demand. This is the "semantic layer" pattern:
# - No data duplication (saves storage cost)
# - Always fresh (computed at query time)
# - No ETL pipeline needed for gold
# - Athena handles the heavy lifting
#
# To query: SELECT * FROM hsl_transport.gold_performance WHERE year='2026'

resource "aws_athena_named_query" "create_gold_view" {
  name        = "create-gold-performance-view"
  description = "Creates the gold_performance view (run once after infrastructure deployment)"
  database    = aws_glue_catalog_database.hsl.name
  workgroup   = "primary"

  query = <<-EOT
    CREATE OR REPLACE VIEW gold_performance AS
    SELECT
        s.feed_timestamp,
        s.route_id,
        COALESCE(r.route_short_name, s.route_id) as route_short_name,
        s.trip_id,
        s.direction_id,
        s.stop_id,
        COALESCE(st.stop_name, CAST(s.stop_id AS varchar)) as stop_name,
        stm.stop_sequence,
        stm.arrival_time as scheduled_arrival,
        date_format(from_unixtime(CAST(s.predicted_arrival AS bigint)), '%H:%i:%s') as predicted_arrival,
        CAST(s.predicted_arrival AS bigint) - (
            CAST(split_part(stm.arrival_time, ':', 1) AS bigint) * 3600 +
            CAST(split_part(stm.arrival_time, ':', 2) AS bigint) * 60 +
            CAST(split_part(stm.arrival_time, ':', 3) AS bigint)
        ) as delay_seconds,
        s.arrival_uncertainty,
        s.year,
        s.month,
        s.day
    FROM silver_realtime s
    LEFT JOIN ref_trips t
        ON CAST(s.route_id AS bigint) = t.route_id
        AND s.direction_id = t.direction_id
        AND s.start_time = t.start_time
    LEFT JOIN ref_stop_times stm
        ON t.trip_id = stm.trip_id
        AND CAST(s.stop_id AS bigint) = stm.stop_id
    LEFT JOIN ref_routes r
        ON CAST(s.route_id AS bigint) = r.route_id
    LEFT JOIN ref_stops st
        ON CAST(s.stop_id AS bigint) = st.stop_id
  EOT
}
