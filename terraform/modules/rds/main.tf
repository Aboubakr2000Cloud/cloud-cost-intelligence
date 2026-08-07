# ── DB SUBNET GROUP ─────────────────────────────────────────────────────
resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-db-subnet-group"
    }
  )
}

# ── DB INSTANCE ─────────────────────────────────────────────────────────
resource "aws_db_instance" "this" {
  identifier            = "${var.name_prefix}-db"
  engine                = "mysql"
  engine_version        = "8.0"
  instance_class        = var.db_instance_class
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]

  multi_az            = false
  publicly_accessible = false

  kms_key_id = var.kms_key_arn

  skip_final_snapshot     = true
  backup_retention_period = 1

  auto_minor_version_upgrade = true # auto-patch minor versions
  copy_tags_to_snapshot      = true

  performance_insights_enabled = false

  deletion_protection = false
  storage_encrypted   = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-db"
    }
  )
}
