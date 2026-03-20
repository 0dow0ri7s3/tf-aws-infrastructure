#=====================================================================
#          DB SUBNET GROUP
#=====================================================================

resource "aws_db_subnet_group" "epicbook_db_subnet_group" {
  name       = "epicbook-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_subnet_a.id,
    aws_subnet.private_subnet_c.id
  ]

  tags = {
    Name = "epicbook-db-subnet-group"
  }
}

#=====================================================================
#         RDS MYSQL INSTANCE
#=====================================================================

resource "aws_db_instance" "epicbook_rds" {
  identifier        = "epicbook-rds"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.epicbook_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name = "epicbook-rds"
  }
}