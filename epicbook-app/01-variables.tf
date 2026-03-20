#=====================================================================
#          REGION
#=====================================================================
variable "aws_region" {
  description = "aws region to deploy all resources"
  type = string
  default = "us-west-1"
}

#=====================================================================
#          NETWORK
#=====================================================================
variable "vpc_cidr" {
  description = "cidr block for the vpc"
  type = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "cidr block for the public subnet where ec2 lives"
  type = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "cidr block for the private subnet where rds database lives"
  type = string
  default = "10.0.2.0/24"
}

variable "private_subnet_cidr_c" {
  description = "second private subnet in another AZ, required by RDS subnet security group"
  type = string
  default = "10.0.3.0/24"
}

#=====================================================================
#          COMPUTE
#=====================================================================

variable "instance_type" {
  description = "ec2 instant type"
  type = string
  default = "t2.micro"
}

variable "key_name" {
  description = "name of the SSH key pair to be attach to the ec2 instance"
  type = string
  default = "epicbook-key"
}

#=====================================================================
#          DATABASE
#=====================================================================

variable "db_name" {
  description = "name of MYSQL database"
  type = string
  default = "bookstore"
}

variable "db_username" {
  description = "Master username for MYSQL database"
  type = string
  default = "admin123"
}

variable "db_password" {
  description = "Master password for RDS — never hardcode in production, use secrets manager"
  type = string
  default = "epicbook123!"
  sensitive = true
}

variable "db_instance_class" {
  description = "RDS instance size"
  type = string
  default = "db.t3.micro"
}

#=====================================================================
#  Your IP auto fetch - No manual update
#=====================================================================

variable "my_ip" {
  description = "Your public IP for SSH access — auto populated via data block"
  type = string
  default = ""
}