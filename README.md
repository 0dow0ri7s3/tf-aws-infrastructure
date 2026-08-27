# tf-aws-infrastructure

Terraform practice builds on AWS. Kept as a learning record.

For production-style infrastructure work, see
[epicbook-ha-infra-terraform](https://github.com/0dow0ri7s3/epicbook-ha-infra-terraform)
— multi-AZ, Auto Scaling, layered security groups, OIDC-authenticated CI.

| Build | What it covers |
|---|---|
| [linux-vm](./linux-vm) | Single EC2 instance, VPC, security group, Nginx |
| [epicbook-app](./epicbook-app) | EC2 with RDS MySQL, Nginx, PM2 — single-instance version |
