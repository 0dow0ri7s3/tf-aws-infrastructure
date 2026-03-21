# EpicBook App — AWS

Deploys the EpicBook full-stack web application on AWS using Terraform. The entire infrastructure — VPC, public and private subnets, EC2, RDS MySQL, security groups, Nginx reverse proxy, and application setup — is fully automated. No manual steps after `terraform apply`.

---

![Architecture](./docs/epicbookvc.png)

---

## What This Builds

**Network**
- VPC (`10.0.0.0/16`)
- Public subnet (`10.0.1.0/24`) — EC2 lives here
- Private subnet A (`10.0.2.0/24`) — RDS primary
- Private subnet B (`10.0.3.0/24`) — RDS subnet group requirement
- Internet Gateway
- Route table with IGW route associated to public subnet only

**Security**
- EC2 security group — SSH (your IP only), HTTP (open)
- RDS security group — MySQL port 3306 from EC2 SG only (SG-to-SG, not CIDR)
- Egress rules on both SGs

**Compute**
- Ubuntu 22.04 LTS EC2 (`t2.micro`)
- SSH key pair
- Public IP enabled
- userdata.sh runs on first boot — installs everything, seeds database, starts app

**Database**
- RDS MySQL 8.0 (`db.t3.micro`)
- Private subnet — no public access
- DB subnet group spanning two AZs
- Sequelize auto-creates tables on first run

**Application**
- Node.js + Express backend
- PM2 process manager keeps app running
- Nginx reverse proxy on port 80 → app on port 8080
- SQL dumps imported automatically on first boot

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) installed
- [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- An active AWS account
- SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`

---

## Project Structure

```
epicbook-app/
├── main.tf           # Provider, Terraform settings, shared data blocks
├── variables.tf      # All input variables in one place
├── outputs.tf        # EC2 IP, RDS endpoint, app URL
├── network.tf        # VPC, subnets, IGW, route tables
├── security.tf       # Security groups and rules
├── compute.tf        # EC2 instance and SSH key pair
├── database.tf       # RDS instance and DB subnet group
├── userdata.sh       # Bootstrap script — full app deployment
├── .gitignore        # Excludes state files and secrets
├── README.md
├── WALKTHROUGH.md
└── docs/
    └── architecture.png
```

For a full step-by-step breakdown see [WALKTHROUGH.md](./WALKTHROUGH.md)

---

## Setup

**1. Clone the repo**
```bash
git clone https://github.com/0dow0ri7s3/tf-aws-infrastructure.git
cd tf-aws-infrastructure/epicbook-app
```

**2. Configure AWS CLI**
```bash
aws configure
```

**3. Initialize Terraform**
```bash
terraform init
```

**4. Plan and apply**
```bash
terraform plan -out=tfplan
terraform apply tfplan
```

RDS takes 10 to 15 minutes to provision. EC2 comes up faster but the bootstrap script needs another 5 to 10 minutes to complete. Total wait time is approximately 20 minutes.

After apply you will see:

```
ec2_public_ip = "x.x.x.x"
rds_endpoint  = "epicbook-rds.xxxxx.us-west-1.rds.amazonaws.com"
app_url       = "http://x.x.x.x"
```

---

## Access the App

Paste the app URL in your browser:
```
http://<ec2_public_ip>
```

---

## SSH Into the VM

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<ec2_public_ip>
```

---

## Verify Everything Is Running

```bash
# Check app process
pm2 status

# Check app is listening on port 8080
ss -tulpn | grep 8080

# Check Nginx
sudo systemctl status nginx

# Check database connectivity
mysql -h <rds_endpoint> -u admin123 -p -e "USE bookstore; SELECT COUNT(*) FROM Book;"
```

---

## Dynamic SSH IP

The SSH rule auto-fetches your current public IP at plan time:

```hcl
data "http" "my_ip" {
  url = "https://api.ipify.org"
}
```

If your IP changes just re-run:
```bash
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Tear Down

```bash
terraform destroy
```

RDS takes 10 to 15 minutes to delete. The VPC will wait until all RDS network interfaces are fully released by AWS before completing. This is normal. Let it run.

---

## Key Lessons

- Multi-file Terraform structure separates concerns and mirrors production practice
- RDS in a private subnet with SG-to-SG access is the production standard for database security
- `templatefile()` injects dynamic values like the RDS endpoint into userdata at plan time
- PM2 must run as the correct user — running as root causes startup issues on reboot
- The app's `config/config.json` was hardcoded to localhost — Terraform overwrites it with real RDS credentials automatically
- RDS needs a DB subnet group spanning two availability zones even for single-AZ deployments
- `skip_final_snapshot = true` allows clean destroy in dev environments
- VPC deletion waits for RDS ENIs to fully detach — this can take 10+ minutes and is expected behavior

---

## Author

**Odoworitse Ab. Afari**
Junior DevOps Engineer
[GitHub](https://github.com/0dow0ri7s3) · [LinkedIn](https://linkedin.com/in/odoworitse-afari)
