locals {
  name_prefix    = "cloud-cost-intelligence-${var.environment}"
  monitor_prefix = "cost-intel-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "Abou"
  }
}

locals {
  lambda_environment = {
    REGION = var.region

    DB_HOST_PARAMETER = aws_ssm_parameter.db_host.name
    DB_PORT_PARAMETER = aws_ssm_parameter.db_port.name
    DB_NAME_PARAMETER = aws_ssm_parameter.db_name.name
    DB_USER_PARAMETER = aws_ssm_parameter.db_user.name

    DB_PASSWORD_SECRET = aws_secretsmanager_secret.db_password.name
  }
}
