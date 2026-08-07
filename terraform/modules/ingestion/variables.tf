variable "name_prefix" {
  type = string
}

variable "collector_function_arn" {
  type = string
}

variable "collector_function_name" {
  type = string
}

variable "anomaly_detector_function_arn" {
  type = string
}

variable "anomaly_detector_function_name" {
  type = string
}

variable "collection_schedule_expression" {
  type    = string
  default = "rate(1 hour)"
}

variable "anomaly_schedule_expression" {
  type    = string
  default = "cron(0 9 * * ? *)"
}

variable "tags" {
  type = map(string)
}
