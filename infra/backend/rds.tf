resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project_name}-postgres16"
  family = "postgres16"
}

resource "aws_db_instance" "postgres" {
  identifier        = "${var.project_name}-db"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username

  # RDS generates, stores and rotates the master password in its own
  # Secrets Manager secret — the password never touches Terraform state or tfvars.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az = false

  # Public so migrations can run from GitHub Actions (outside the VPC).
  # Access is still gated by the RDS security group — see security_groups.tf.
  publicly_accessible = true

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-db-final-snapshot"
  deletion_protection       = true

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
}
