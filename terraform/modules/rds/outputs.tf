output "rds_endpoint" {
  value     = aws_db_instance.this.endpoint
  sensitive = true
}
output "db_host" { value = aws_db_instance.this.address }
output "db_port" { value = aws_db_instance.this.port }
output "db_name" { value = aws_db_instance.this.db_name }
output "db_instance_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.identifier
}
