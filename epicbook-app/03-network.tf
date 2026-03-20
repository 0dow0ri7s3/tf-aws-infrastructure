#=====================================================================
#          VPC
#=====================================================================

resource "aws_vpc" "epicbook_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true

    tags = {
        name = "epicbook-vpc"
    }
}

#=====================================================================
#          PUBLIC SUBNET - EC2 LIVES HERE
#=====================================================================

resource "aws_subnet" "public_subnet" {
  vpc_id = aws_vpc.epicbook_vpc.id
  cidr_block = var.public_subnet_cidr
  availability_zone = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    name = "epicbook-public-subnet"
  }
}

#=====================================================================
#          PRIVATE SUBNET A — RDS primary
#=====================================================================
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.epicbook_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "epicbook-private-subnet-a"
  }
}

#=====================================================================
#          PRIVATE SUBNET C — required by RDS subnet group
#=====================================================================

resource "aws_subnet" "private_subnet_c" {
  vpc_id            = aws_vpc.epicbook_vpc.id
  cidr_block        = var.private_subnet_cidr_c
  availability_zone = "${var.aws_region}c"

  tags = {
    Name = "epicbook-private-subnet-c"
  }
}

#=====================================================================
#          INTERNET GATEWAY
#=====================================================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.epicbook_vpc.id

  tags = {
    Name = "epicbook-igw"
  }
}

#=====================================================================
#          PUBLIC ROUTE TABLE
#=====================================================================

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.epicbook_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "epicbook-public-rt"
  }
}

#=====================================================================
#          ASSOCIATE PUBLIC ROUTE TABLE TO PUBLIC SUBNET
#=====================================================================

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}