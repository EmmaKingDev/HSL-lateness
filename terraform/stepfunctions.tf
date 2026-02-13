resource "aws_sfn_state_machine" "hsl_pipeline" {
  name     = "hsl-data-pipeline"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "HSL realtime data pipeline - Bronze -> Silver (Gold is a view)"
    StartAt = "FetchRealtimeData"
    States = {
      FetchRealtimeData = {
        Type     = "Task"
        Resource = aws_lambda_function.fetch_realtime.arn
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 30
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "PipelineFailed"
          }
        ]
        Next = "FlattenData"
      }
      FlattenData = {
        Type     = "Task"
        Resource = aws_lambda_function.flatten_data.arn
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 10
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "PipelineFailed"
          }
        ]
        Next = "PipelineSucceeded"
      }
      PipelineSucceeded = {
        Type = "Succeed"
      }
      PipelineFailed = {
        Type  = "Fail"
        Error = "PipelineError"
        Cause = "One or more steps in the HSL pipeline failed after retries"
      }
    }
  })
}

# Note: The Gold layer (gold_performance) is implemented as an Athena VIEW
# that joins silver_realtime with reference tables on-demand.
# See athena.tf for the view definition.
#
# This is the "semantic layer" pattern:
# - No ETL step needed (no data movement)
# - Always fresh (computed at query time)
# - Lower storage cost (no data duplication)
