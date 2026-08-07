output "events_table_name" {
  description = "DynamoDB events table name"
  value       = aws_dynamodb_table.events.name
}

output "events_table_arn" {
  description = "DynamoDB events table ARN"
  value       = aws_dynamodb_table.events.arn
}
