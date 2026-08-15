resource "aws_lambda_invocation" "db_migration" {
  function_name = module.db_migrator_lambda.function_name

  input = jsonencode({
    action = "migrate"
  })

  depends_on = [
    module.rds,
    module.db_migrator_lambda
  ]
}
