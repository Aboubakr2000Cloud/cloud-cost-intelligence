output "cluster_name" { value = aws_ecs_cluster.this.name }
output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "service_name" { value = aws_ecs_service.this.name }
output "task_definition" { value = aws_ecs_task_definition.this.arn }
output "log_group_name" { value = aws_cloudwatch_log_group.this.name }
output "task_definition_family" { value = aws_ecs_task_definition.this.family }
output "container_name" { value = var.container_name }
