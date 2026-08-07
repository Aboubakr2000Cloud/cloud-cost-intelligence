output "sns_topic_arn" {
  description = "SNS topic ARN for monitoring alerts"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_arn" {
  description = "CloudWatch dashboard ARN"
  value       = aws_cloudwatch_dashboard.main.dashboard_arn
}

output "budget_name" {
  description = "AWS Budget name"
  value       = aws_budgets_budget.main.name
}

