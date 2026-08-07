# ── VPC ──────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# ── Security Groups ───────────────────────────────────────────────
module "security_groups" {
  source = "./modules/security_groups"

  vpc_id = module.vpc.vpc_id

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# ── RDS ───────────────────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  name_prefix = local.name_prefix

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security_groups.rds_sg_id

  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = random_password.db.result
  db_instance_class = var.db_instance_class

  kms_key_arn = module.security.kms_key_arn

  tags = local.common_tags
}

# ── DYNAMODB ───────────────────────────────────────────────────────────
module "dynamodb" {
  source = "./modules/dynamodb"

  name_prefix = local.name_prefix
  kms_key_arn = module.security.kms_key_arn

  tags = local.common_tags
}

# ── SECURITY ───────────────────────────────────────────────────────────
module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix

  account_id = data.aws_caller_identity.current.account_id

  enable_guardduty = false

  tags = local.common_tags
}

# ── ECR ───────────────────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  repository_name = var.repository_name

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# ── LAMBDAS ───────────────────────────────────────────────────────────
module "collector_lambda" {
  source = "./modules/lambda"

  function_name = "${local.name_prefix}-collector"

  role_arn = aws_iam_role.collector.arn

  handler = "app.lambda_handler"

  filename         = "${path.module}/../build/collector.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/collector.zip")

  private_subnet_ids = module.vpc.private_subnet_ids
  lambda_sg_id       = module.security_groups.lambda_sg_id

  environment_variables = merge(
    local.lambda_environment,
    {
      SNS_TOPIC_ARN = module.monitoring.sns_topic_arn
    }
  )

  tags = local.common_tags
}

module "anomaly_detector_lambda" {
  source = "./modules/lambda"

  function_name = "${local.name_prefix}-anomaly_detector"

  role_arn = aws_iam_role.anomaly_detector.arn

  handler = "app.lambda_handler"

  filename         = "${path.module}/../build/anomaly_detector.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/anomaly_detector.zip")

  private_subnet_ids = module.vpc.private_subnet_ids
  lambda_sg_id       = module.security_groups.lambda_sg_id

  environment_variables = merge(
    local.lambda_environment,
    {
      SNS_TOPIC_ARN = module.monitoring.sns_topic_arn
    }
  )

  tags = local.common_tags
}

module "data_seeder_lambda" {
  source = "./modules/lambda"

  function_name = "${local.name_prefix}-data_seeder"

  role_arn = aws_iam_role.data_seeder.arn

  handler = "app.lambda_handler"

  filename         = "${path.module}/../build/data_seeder.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/data_seeder.zip")

  private_subnet_ids = module.vpc.private_subnet_ids
  lambda_sg_id       = module.security_groups.lambda_sg_id

  environment_variables = local.lambda_environment

  tags = local.common_tags
}

# ── INGESTION ───────────────────────────────────────────────────────────
module "ingestion" {
  source = "./modules/ingestion"

  name_prefix = local.name_prefix

  collector_function_arn  = module.collector_lambda.function_arn
  collector_function_name = module.collector_lambda.function_name

  anomaly_detector_function_arn  = module.anomaly_detector_lambda.function_arn
  anomaly_detector_function_name = module.anomaly_detector_lambda.function_name

  tags = local.common_tags
}

# ── ECS ───────────────────────────────────────────────────────────
module "ecs" {
  source = "./modules/ecs"

  name_prefix = local.name_prefix

  cluster_name   = "${local.name_prefix}-cluster"
  service_name   = var.service_name
  container_name = var.container_name
  image_url      = "${module.ecr.repository_url}:bootstrap"

  private_subnet_ids = module.vpc.private_subnet_ids
  ecs_task_sg_id     = module.security_groups.ecs_task_sg_id

  target_group_arn = module.alb.target_group_arn
  desired_count    = var.ecs_desired_count

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  db_secret_arn         = aws_secretsmanager_secret.db_password.arn
  db_user_parameter_arn = aws_ssm_parameter.db_user.arn
  db_host_parameter_arn = aws_ssm_parameter.db_host.arn
  db_name_parameter_arn = aws_ssm_parameter.db_name.arn
  db_port_parameter_arn = aws_ssm_parameter.db_port.arn

  log_group_name = "/ecs/${local.name_prefix}"

  region = var.region

  tags = local.common_tags
}

# ── ALB ───────────────────────────────────────────────────────────
module "alb" {
  source = "./modules/alb"

  name_prefix = local.name_prefix

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id

  tags = local.common_tags
}

# ── FRONTEND ───────────────────────────────────────────────────────────
module "frontend" {
  source = "./modules/frontend"

  name_prefix = local.name_prefix

  tags = local.common_tags
}

# ── CLOUDWATCH ───────────────────────────────────────────────────────────
module "monitoring" {
  source = "./modules/monitoring"

  monitor_prefix = local.monitor_prefix
  name_prefix    = local.name_prefix

  alert_email = var.alert_email

  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name

  collector_function_name        = module.collector_lambda.function_name
  anomaly_detector_function_name = module.anomaly_detector_lambda.function_name

  alb_arn_suffix = module.alb.alb_arn_suffix

  db_instance_identifier = module.rds.db_instance_identifier

  log_group_name = module.ecs.log_group_name

  region = var.region

  tags = local.common_tags
}






