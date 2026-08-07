output "eventbridge_rule_arn" {
  value = aws_cloudwatch_event_rule.collector_schedule.arn
}

output "eventbridge_rule_name" {
  value = aws_cloudwatch_event_rule.collector_schedule.name
}

output "anomaly_rule_arn" {
  value = aws_cloudwatch_event_rule.anomaly_schedule.arn
}

output "anomaly_rule_name" {
  value = aws_cloudwatch_event_rule.anomaly_schedule.name
}
