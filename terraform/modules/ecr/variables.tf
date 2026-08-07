variable "repository_name" { type = string }
variable "container_port" {
  type    = number
  default = 8080
}
variable "name_prefix" { type = string }
variable "tags" { type = map(string) }


