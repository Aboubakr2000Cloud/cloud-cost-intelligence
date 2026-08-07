variable "name_prefix" { type = string }
variable "monitor_prefix" { type = string }
variable "alert_email" { type = string }
variable "region" { type = string }
variable "ecs_cluster_name" { type = string }
variable "ecs_service_name" { type = string }
variable "alb_arn_suffix" { type = string }
variable "db_instance_identifier" { type = string }
variable "log_group_name" { type = string }
variable "collector_function_name" { type = string }
variable "anomaly_detector_function_name" { type = string }
variable "monthly_budget_limit" {
  type    = number
  default = 100
}
variable "tags" {
  type = map(string)
}
