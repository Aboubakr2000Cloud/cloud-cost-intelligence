resource "aws_lambda_function" "this" {
  function_name = var.function_name

  role    = var.role_arn
  handler = var.handler
  runtime = var.runtime

  filename         = var.filename
  source_code_hash = var.source_code_hash

  memory_size = var.memory_size
  timeout     = var.timeout

  architectures = ["x86_64"]

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = var.environment_variables
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  tags = merge(
    var.tags,
    {
      Name = var.function_name
    }
  )
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.function_name}-logs"
    }
  )
}
