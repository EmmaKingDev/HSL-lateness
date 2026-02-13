data "archive_file" "fetch_realtime" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/fetch_realtime"
  output_path = "${path.module}/zip/fetch_realtime.zip"
}

data "archive_file" "flatten_data" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/flatten_data"
  output_path = "${path.module}/zip/flatten_data.zip"
}

data "archive_file" "generate_stats" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/generate_stats"
  output_path = "${path.module}/zip/generate_stats.zip"
}

resource "aws_lambda_function" "fetch_realtime" {
  function_name    = "hsl-fetch-realtime"
  filename         = data.archive_file.fetch_realtime.output_path
  source_code_hash = data.archive_file.fetch_realtime.output_base64sha256
  layers           = [aws_lambda_layer_version.dependencies.arn]
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_fetch.arn
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      BRONZE_BUCKET = aws_s3_bucket.data_bucket[0].id
    }
  }
}

resource "aws_lambda_function" "flatten_data" {
  function_name    = "hsl-flatten-data"
  filename         = data.archive_file.flatten_data.output_path
  source_code_hash = data.archive_file.flatten_data.output_base64sha256
  layers           = [aws_lambda_layer_version.dependencies.arn]
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_flatten.arn
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      BRONZE_BUCKET = aws_s3_bucket.data_bucket[0].id
      SILVER_BUCKET = aws_s3_bucket.data_bucket[1].id
    }
  }
}

resource "aws_lambda_function" "generate_stats" {
  function_name    = "hsl-generate-stats"
  filename         = data.archive_file.generate_stats.output_path
  source_code_hash = data.archive_file.generate_stats.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_stats.arn
  timeout          = 120
  memory_size      = 256

  environment {
    variables = {
      OUTPUT_BUCKET  = aws_s3_bucket.data_bucket[4].id  # athena-results bucket
      RESULTS_BUCKET = aws_s3_bucket.data_bucket[4].id
    }
  }
}

# Note: Gold layer enrichment is now handled by Athena via Step Functions
# native integration (see stepfunctions.tf EnrichGold state)

resource "aws_lambda_layer_version" "dependencies" {
  layer_name          = "hsl-dependencies"
  filename            = "${path.module}/../layers/lambda_layer.zip"
  compatible_runtimes = ["python3.12"]
  source_code_hash    = filebase64sha256("${path.module}/../layers/lambda_layer.zip")
}
