resource "aws_ssm_parameter" "db_host" {
  name  = "/${local.name_prefix}/db-host"
  type  = "String"
  value = module.rds.db_host

  tags = merge(
    local.common_tags,
    {
      Name = local.name_prefix
    }
  )
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/${local.name_prefix}/db-name"
  type  = "String"
  value = var.db_name

  tags = merge(
    local.common_tags,
    {
      Name = local.name_prefix
    }
  )
}

resource "aws_ssm_parameter" "db_port" {
  name  = "/${local.name_prefix}/db-port"
  type  = "String"
  value = "3306"

  tags = merge(
    local.common_tags,
    {
      Name = local.name_prefix
    }
  )
}

resource "aws_ssm_parameter" "db_user" {
  name  = "/${local.name_prefix}/db-user"
  type  = "String"
  value = var.db_username

  tags = merge(
    local.common_tags,
    {
      Name = local.name_prefix
    }
  )
}
