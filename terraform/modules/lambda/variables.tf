variable "function_name" {
  description = "Lambda function name"
  type        = string
}

variable "role_arn" {
  description = "IAM role ARN"
  type        = string
}

variable "handler" {
  description = "Lambda handler"
  type        = string
}

variable "filename" {
  description = "Deployment package"
  type        = string
}

variable "source_code_hash" {
  description = "Hash of deployment package"
  type        = string
}

variable "environment_variables" {
  description = "Lambda environment variables"
  type        = map(string)
  default     = {}
}

variable "memory_size" {
  description = "Memory size (MB)"
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Timeout (seconds)"
  type        = number
  default     = 30
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.11"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Lambda VPC configuration"
  type        = list(string)
}

variable "lambda_sg_id" {
  description = "Security Group attached to the Lambda"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
}
