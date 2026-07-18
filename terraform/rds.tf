# ---------- Random master password, never hardcoded ----------
resource "random_password" "db_master" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()-_=+"
}

# ---------- Store credentials in Secrets Manager, not in state-readable plaintext outputs ----------
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}-db-credentials"
  description             = "RDS MySQL master credentials for WordPress"
  recovery_window_in_days = 0 # allows immediate deletion on destroy, no 7-30 day hold

  tags = {
    Name = "${var.project_name}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_master.result
    dbname   = var.db_name
    host     = aws_db_instance.main.address
    port     = 3306
  })
}

# ---------- DB subnet group: spans the isolated data subnets across both AZs ----------
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.data[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ---------- RDS MySQL, Multi-AZ ----------
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-mysql"
  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master.result

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:30-mon:05:30"

  # Clean, one-command destroy — no manual snapshot cleanup required
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "${var.project_name}-mysql"
  }
}
