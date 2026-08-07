# EventBridge rule — hourly collection
resource "aws_cloudwatch_event_rule" "collector_schedule" {
  name                = "${var.name_prefix}-collector-schedule"
  description         = "Schedule hourly cost data collection"
  schedule_expression = var.collection_schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "collector" {
  rule      = aws_cloudwatch_event_rule.collector_schedule.name
  target_id = "cost-collector"
  arn       = var.collector_function_arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.collector_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.collector_schedule.arn
}

# Daily anomaly detection — runs at 9am UTC
resource "aws_cloudwatch_event_rule" "anomaly_schedule" {
  name                = "${var.name_prefix}-anomaly-schedule-check"
  description         = "Schedule daily cost anomaly detection"
  schedule_expression = var.anomaly_schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "anomaly_detector" {
  rule      = aws_cloudwatch_event_rule.anomaly_schedule.name
  target_id = "anomaly-detector"
  arn       = var.anomaly_detector_function_arn
}

resource "aws_lambda_permission" "eventbridge_anomaly" {
  statement_id  = "AllowEventBridgeAnomalyInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.anomaly_detector_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.anomaly_schedule.arn
}
