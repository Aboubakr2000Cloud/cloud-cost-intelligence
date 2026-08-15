resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${local.name_prefix}/db-password"
  kms_key_id              = module.security.kms_key_arn
  recovery_window_in_days = 0

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-db-password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
  })
}
