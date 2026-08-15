variable "account_id" {
  description = "AWS Account ID"
  type        = string
}
variable "name_prefix" { type = string }
variable "tags" {
  type = map(string)
}
variable "enable_guardduty" {
  type    = bool
  default = true
}

variable "ecs_execution_role_arn" {
  type = string
}

