environment = "prod"

region = "eu-west-1"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
azs                  = ["eu-west-1a", "eu-west-1b"]

# Database
db_instance_class = "db.t3.micro"
db_name           = "costintelligence"
db_username       = "admin"

# ECS
service_name    = "cost-api"
repository_name = "cost-api"
container_name  = "cost-api"

ecs_desired_count = 2

# Monitoring
alert_email = "aboubacre.ijannane@gmail.com"
