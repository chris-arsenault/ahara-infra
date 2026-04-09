# =============================================================================
# Shared PostgreSQL RDS instance (smallest viable size)
# =============================================================================

resource "aws_db_subnet_group" "ahara" {
  name       = "${local.prefix}-db"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "rds" {
  name        = "${local.prefix}-rds"
  description = "Shared RDS access"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.42.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "sg:role"  = "rds"
    "sg:scope" = local.prefix
  }
}

resource "random_password" "rds_master" {
  length  = 24
  special = false
}

resource "aws_db_instance" "ahara" {
  identifier = "${local.prefix}-shared"

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = local.prefix
  username = "${local.prefix}_admin"
  password = random_password.rds_master.result

  db_subnet_group_name   = aws_db_subnet_group.ahara.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false
  publicly_accessible = false
  deletion_protection = true

  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.prefix}-shared-final"

  backup_retention_period = 7
  backup_window           = "04:00-05:00"
  maintenance_window      = "sun:06:00-sun:07:00"

  performance_insights_enabled = false

  lifecycle {
    ignore_changes = [engine_version]
  }
}
