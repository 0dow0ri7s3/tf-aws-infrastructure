#=====================================================================
#          EC2 SECURITY GROUP
#=====================================================================

resource "aws_security_group" "ec2_sg" {
  name        = "epicbook-ec2-sg"
  description = "Allow SSH from my IP and HTTP from anywhere"
  vpc_id      = aws_vpc.epicbook_vpc.id

  tags = {
    Name = "epicbook-ec2-sg"
  }
}

# SSH — your IP only
resource "aws_vpc_security_group_ingress_rule" "ec2_ssh" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "${chomp(data.http.my_ip.response_body)}/32"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# HTTP — open to everyone
resource "aws_vpc_security_group_ingress_rule" "ec2_http" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Outbound — allow all
resource "aws_vpc_security_group_egress_rule" "ec2_outbound" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

#=====================================================================
#          RDS SECURITY GROUP
#=====================================================================

resource "aws_security_group" "rds_sg" {
  name        = "epicbook-rds-sg"
  description = "Allow MySQL only from EC2 security group"
  vpc_id      = aws_vpc.epicbook_vpc.id

  tags = {
    Name = "epicbook-rds-sg"
  }
}

# MySQL — from EC2 SG only, not a CIDR
resource "aws_vpc_security_group_ingress_rule" "rds_mysql" {
  security_group_id            = aws_security_group.rds_sg.id
  referenced_security_group_id = aws_security_group.ec2_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

# Outbound — allow all
resource "aws_vpc_security_group_egress_rule" "rds_outbound" {
  security_group_id = aws_security_group.rds_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}