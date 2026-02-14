# --- Trust policies ---

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "stepfunctions_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "eventbridge_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "athena_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# --- Roles ---

resource "aws_iam_role" "lambda_fetch" {
  name               = "hsl-lambda-fetch-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "lambda_flatten" {
  name               = "hsl-lambda-flatten-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "step_functions" {
  name               = "hsl-stepfunctions-role"
  assume_role_policy = data.aws_iam_policy_document.stepfunctions_assume_role.json
}

resource "aws_iam_role" "eventbridge" {
  name               = "hsl-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume_role.json
}

resource "aws_iam_role" "athena_query" {
  name               = "hsl-athena-query-role"
  assume_role_policy = data.aws_iam_policy_document.athena_assume_role.json
}

resource "aws_iam_role" "lambda_stats" {
  name               = "hsl-lambda-stats-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# --- Permission policies ---

data "aws_iam_policy_document" "lambda_fetch_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data_bucket[0].arn}/*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "lambda_flatten_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data_bucket[0].arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data_bucket[1].arn}/*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "stepfunctions_permissions" {
  # Invoke Lambda functions
  statement {
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.fetch_realtime.arn,
      aws_lambda_function.flatten_data.arn
    ]
  }

  # Athena query execution (for Gold layer)
  statement {
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:StopQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults"
    ]
    resources = ["*"]
  }

  # Glue catalog access (Athena needs this)
  statement {
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetPartitions",
      "glue:GetPartition",
      "glue:BatchCreatePartition",
      "glue:CreatePartition"
    ]
    resources = ["*"]
  }

  # S3 read access for silver and reference buckets
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.data_bucket[1].arn}/*",
      "${aws_s3_bucket.data_bucket[3].arn}/*"
    ]
  }

  # S3 write access for gold and results buckets
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      "${aws_s3_bucket.data_bucket[2].arn}/*",
      "${aws_s3_bucket.data_bucket[4].arn}/*"
    ]
  }

  # S3 list access for partition discovery
  statement {
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.data_bucket[1].arn,
      aws_s3_bucket.data_bucket[2].arn,
      aws_s3_bucket.data_bucket[3].arn,
      aws_s3_bucket.data_bucket[4].arn
    ]
  }
}

data "aws_iam_policy_document" "eventbridge_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "lambda_stats_permissions" {
  # Athena query execution
  statement {
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults"
    ]
    resources = ["*"]
  }

  # Glue catalog access
  statement {
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetPartition",
      "glue:GetPartitions"
    ]
    resources = ["*"]
  }

  # S3 read for silver and reference
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.data_bucket[1].arn}/*",
      "${aws_s3_bucket.data_bucket[3].arn}/*"
    ]
  }

  # S3 write for query results and public JSON
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.data_bucket[4].arn}/*"]
  }

  # S3 list for partition discovery
  statement {
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.data_bucket[1].arn,
      aws_s3_bucket.data_bucket[3].arn,
      aws_s3_bucket.data_bucket[4].arn
    ]
  }

  # CloudWatch logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "athena_permissions" {
  # Athena itself
  statement {
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults"
    ]
    resources = ["*"]
  }

  # Glue catalog — Athena needs this to find table definitions
  statement {
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetPartitions"
    ]
    resources = ["*"]
  }

  # Read silver data
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data_bucket[1].arn}/*"]
  }

  # Read gold data
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data_bucket[2].arn}/*"]
  }

  # Read reference data
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data_bucket[3].arn}/*"]
  }

  # Write query results
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.data_bucket[4].arn}/*"]
  }

  # List buckets — Athena needs this to discover partitions
  statement {
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.data_bucket[1].arn,
      aws_s3_bucket.data_bucket[2].arn,
      aws_s3_bucket.data_bucket[3].arn,
      aws_s3_bucket.data_bucket[4].arn
    ]
  }

  # CloudWatch logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

# --- Attach policies to roles ---

resource "aws_iam_role_policy" "lambda_fetch" {
  name   = "lambda-fetch-policy"
  role   = aws_iam_role.lambda_fetch.id
  policy = data.aws_iam_policy_document.lambda_fetch_permissions.json
}

resource "aws_iam_role_policy" "lambda_flatten" {
  name   = "lambda-flatten-policy"
  role   = aws_iam_role.lambda_flatten.id
  policy = data.aws_iam_policy_document.lambda_flatten_permissions.json
}

resource "aws_iam_role_policy" "step_functions" {
  name   = "stepfunctions-policy"
  role   = aws_iam_role.step_functions.id
  policy = data.aws_iam_policy_document.stepfunctions_permissions.json
}

resource "aws_iam_role_policy" "eventbridge" {
  name   = "eventbridge-policy"
  role   = aws_iam_role.eventbridge.id
  policy = data.aws_iam_policy_document.eventbridge_permissions.json
}

resource "aws_iam_role_policy" "athena_query" {
  name   = "athena-query-policy"
  role   = aws_iam_role.athena_query.id
  policy = data.aws_iam_policy_document.athena_permissions.json
}

resource "aws_iam_role_policy" "lambda_stats" {
  name   = "lambda-stats-policy"
  role   = aws_iam_role.lambda_stats.id
  policy = data.aws_iam_policy_document.lambda_stats_permissions.json
}
