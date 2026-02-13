resource "aws_cloudwatch_event_rule" "hsl_schedule" {
  name                = "hsl-pipeline-schedule"
  description         = "Triggers HSL data pipeline every 15 minutes"
  schedule_expression = "rate(15 minutes)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "start_pipeline" {
  rule     = aws_cloudwatch_event_rule.hsl_schedule.name
  arn      = aws_sfn_state_machine.hsl_pipeline.arn
  role_arn = aws_iam_role.eventbridge.arn
}

# Daily stats generation (for public dashboard)
resource "aws_cloudwatch_event_rule" "daily_stats" {
  name                = "hsl-daily-stats"
  description         = "Generates public stats JSON once per day"
  schedule_expression = "cron(5 0 * * ? *)"  # 00:05 UTC daily
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "generate_stats" {
  rule = aws_cloudwatch_event_rule.daily_stats.name
  arn  = aws_lambda_function.generate_stats.arn
}

resource "aws_lambda_permission" "allow_eventbridge_stats" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generate_stats.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_stats.arn
}
