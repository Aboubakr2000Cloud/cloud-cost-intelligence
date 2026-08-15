output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS"
  value       = module.alb.alb_dns_name
}

output "cloudfront_url" {
  description = "CloudFront distribution URL"
  value       = module.frontend.cloudfront_url
}

output "db_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_host
}

output "db_name" {
  description = "Database name"
  value       = module.rds.db_name
}

output "repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}

output "collector_lambda_name" {
  description = "Collector Lambda function"
  value       = module.collector_lambda.function_name
}

output "anomaly_detector_lambda_name" {
  description = "Anomaly Detector Lambda function"
  value       = module.anomaly_detector_lambda.function_name
}

output "data_seeder_lambda_name" {
  description = "Data Seeder Lambda function"
  value       = module.data_seeder_lambda.function_name
}

output "dashboard_name" {
  description = "CloudWatch dashboard"
  value       = module.monitoring.dashboard_name
}

output "sns_topic_arn" {
  description = "SNS topic for alerts"
  value       = module.monitoring.sns_topic_arn
}

output "frontend_bucket_name" {
  description = "Frontend S3 bucket"
  value       = module.frontend.s3_bucket_name
}

output "kms_key_arn" {
  description = "Application KMS key ARN"
  value       = module.security.kms_key_arn
}

output "events_table_name" {
  description = "Events table name"
  value       = module.dynamodb.events_table_name
}

output "events_table_arn" {
  description = "Events table ARN"
  value       = module.dynamodb.events_table_arn
}

output "db_verifier_lambda_name" {
  description = "Database verification Lambda function name"
  value       = module.db_verifier_lambda.function_name
}
