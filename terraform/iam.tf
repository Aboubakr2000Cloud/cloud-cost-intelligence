##################################################
# ECS Assume Role Policy
##################################################

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}

##################################################
# Lambda Assume Role Policy
##################################################

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}

##################################################
# ECS Execution Role
##################################################

resource "aws_iam_role" "ecs_execution" {
  name = "${local.name_prefix}-ecs-execution-role"

  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

##################################################
# ECS Task Role
##################################################

resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = local.common_tags
}

##################################################
# ECS Exec Permissions
##################################################

resource "aws_iam_role_policy" "ecs_exec" {
  name = "${local.name_prefix}-ecs-exec"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECSExec"
        Effect = "Allow"

        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]

        Resource = "*"
      }
    ]
  })
}

##################################################
# Collector Lambda Role
##################################################

resource "aws_iam_role" "collector" {
  name = "${local.name_prefix}-collector-role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

##################################################
# Anomaly Detector Lambda Role
##################################################

resource "aws_iam_role" "anomaly_detector" {
  name = "${local.name_prefix}-anomaly-detector-role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

##################################################
# Data Seeder Lambda Role
##################################################

resource "aws_iam_role" "data_seeder" {
  name = "${local.name_prefix}-data-seeder-role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

##################################################
# Lambda Basic Execution Role
##################################################

resource "aws_iam_role_policy_attachment" "collector_basic_execution" {
  role       = aws_iam_role.collector.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "anomaly_detector_basic_execution" {
  role       = aws_iam_role.anomaly_detector.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "data_seeder_basic_execution" {
  role       = aws_iam_role.data_seeder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

##################################################
# Lambda VPC Access
##################################################

resource "aws_iam_role_policy_attachment" "collector_vpc_access" {
  role       = aws_iam_role.collector.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "anomaly_detector_vpc_access" {
  role       = aws_iam_role.anomaly_detector.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "data_seeder_vpc_access" {
  role       = aws_iam_role.data_seeder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

##################################################
# Secrets Manager Access
##################################################

resource "aws_iam_policy" "secrets_access" {
  name        = "${local.name_prefix}-secrets-access"
  description = "Allow reading database secrets"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "secretsmanager:GetSecretValue"
      ]

      Resource = aws_secretsmanager_secret.db_password.arn
    }]
  })

  tags = local.common_tags
}

##################################################
# Parameter Store Access
##################################################

resource "aws_iam_policy" "parameter_store_access" {
  name        = "${local.name_prefix}-parameter-store-access"
  description = "Allow reading application configuration"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]

      Resource = [
        aws_ssm_parameter.db_host.arn,
        aws_ssm_parameter.db_name.arn,
        aws_ssm_parameter.db_port.arn,
        aws_ssm_parameter.db_user.arn
      ]
    }]
  })

  tags = local.common_tags
}

##################################################
# Cost Explorer Access
##################################################

resource "aws_iam_policy" "cost_explorer_access" {
  name        = "${local.name_prefix}-cost-explorer-access"
  description = "Allow querying AWS Cost Explorer"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "ce:GetCostAndUsage",
        "ce:GetCostForecast",
        "ce:GetDimensionValues"
      ]

      Resource = "*"
    }]
  })

  tags = local.common_tags
}

##################################################
# DynamoDB Access
##################################################

resource "aws_iam_policy" "dynamodb_access" {
  name        = "${local.name_prefix}-dynamodb-access"
  description = "Allow Lambda functions to access events table"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]

      Resource = module.dynamodb.events_table_arn
    }]
  })

  tags = local.common_tags
}

##################################################
# SNS Publish
##################################################

resource "aws_iam_policy" "sns_publish" {
  name        = "${local.name_prefix}-sns-publish"
  description = "Allow publishing anomaly alerts"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "sns:Publish"
      ]

      Resource = module.monitoring.sns_topic_arn
    }]
  })

  tags = local.common_tags
}

##################################################
# ECS Task Role Attachments
##################################################

resource "aws_iam_role_policy_attachment" "ecs_task_secrets" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_role_policy_attachment" "ecs_task_parameter_store" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.parameter_store_access.arn
}

##################################################
# Collector Role Attachments
##################################################

resource "aws_iam_role_policy_attachment" "collector_secrets" {
  role       = aws_iam_role.collector.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_role_policy_attachment" "collector_parameter_store" {
  role       = aws_iam_role.collector.name
  policy_arn = aws_iam_policy.parameter_store_access.arn
}

resource "aws_iam_role_policy_attachment" "collector_cost_explorer" {
  role       = aws_iam_role.collector.name
  policy_arn = aws_iam_policy.cost_explorer_access.arn
}

resource "aws_iam_role_policy_attachment" "collector_dynamodb" {
  role       = aws_iam_role.collector.name
  policy_arn = aws_iam_policy.dynamodb_access.arn
}

##################################################
# Anomaly Detector Role Attachments
##################################################

resource "aws_iam_role_policy_attachment" "anomaly_detector_secrets" {
  role       = aws_iam_role.anomaly_detector.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_role_policy_attachment" "anomaly_detector_parameter_store" {
  role       = aws_iam_role.anomaly_detector.name
  policy_arn = aws_iam_policy.parameter_store_access.arn
}

resource "aws_iam_role_policy_attachment" "anomaly_detector_dynamodb" {
  role       = aws_iam_role.anomaly_detector.name
  policy_arn = aws_iam_policy.dynamodb_access.arn
}

resource "aws_iam_role_policy_attachment" "anomaly_detector_sns" {
  role       = aws_iam_role.anomaly_detector.name
  policy_arn = aws_iam_policy.sns_publish.arn
}

##################################################
# Data Seeder Role Attachments
##################################################

resource "aws_iam_role_policy_attachment" "data_seeder_secrets" {
  role       = aws_iam_role.data_seeder.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_role_policy_attachment" "data_seeder_parameter_store" {
  role       = aws_iam_role.data_seeder.name
  policy_arn = aws_iam_policy.parameter_store_access.arn
}

resource "aws_iam_role_policy_attachment" "data_seeder_dynamodb" {
  role       = aws_iam_role.data_seeder.name
  policy_arn = aws_iam_policy.dynamodb_access.arn
}
