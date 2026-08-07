variable "name_prefix" {
  description = "Project name prefix"
  type        = string
}

variable "kms_key_arn" {
  type = string
}

variable "tags" {
  type = map(string)
}
