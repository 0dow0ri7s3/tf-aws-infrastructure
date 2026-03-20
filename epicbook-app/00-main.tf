#=====================================================================
#          Terraform settings
#=====================================================================

terraform {
  required_version = ">=1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.0"
    }
    http = {
        source = "hashicorp/http"
        version = "~>3.0"
    }
  }
}

#=====================================================================
#          PROVIDER
#=====================================================================

provider "aws" {
  region = var.aws_region
}

#=====================================================================
#          fetch your current public ip
#=====================================================================

data "http" "my_ip" {
  url = "https://api.ipify.org"
}

#=====================================================================
#          REFETCH LATEST UBUNTU 22.04 AMI 
#=====================================================================

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

