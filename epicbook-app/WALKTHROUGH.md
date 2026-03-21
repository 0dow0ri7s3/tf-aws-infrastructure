# Walkthrough — EpicBook App on AWS

This guide walks through the full deployment of the EpicBook web application on AWS using Terraform. Every resource, every command, every decision is explained. If you want to understand not just what was built but why each piece exists and how it connects, this is the document.

---

## What Are We Building?

A production-style full-stack web application running on AWS:

- A **Node.js Express** backend
- A **MySQL database** managed by AWS RDS
- **Nginx** as a reverse proxy serving traffic on port 80
- **PM2** keeping the Node app alive permanently
- All provisioned with **Terraform** — zero manual cloud console clicks

The architecture separates the application layer (EC2 in a public subnet) from the database layer (RDS in a private subnet with no internet access). This is the standard secure pattern used in real production systems.

---

## Architecture Overview

```
Internet
    |
    | HTTP port 80
    | SSH port 22 (your IP only)
    |
Internet Gateway
    |
Public Route Table (0.0.0.0/0 → IGW)
    |
Public Subnet 10.0.1.0/24
    |
EC2 Ubuntu 22.04
├── Nginx (port 80) → proxies to Node.js (port 8080)
├── PM2 → keeps Node.js running
└── mysql-client → connects to RDS
    |
    | Port 3306 only
    | EC2 SG reference (not CIDR)
    |
Private Subnet 10.0.2.0/24
    |
RDS MySQL 8.0
└── No public access
    No IGW route
    No internet exposure
```

→ **SS1** — export the architecture diagram from draw.io and save to `docs/architecture.png`

---

## Project File Structure

```
epicbook-app/
├── main.tf           # Entry point — provider and shared data blocks
├── variables.tf      # All configurable values in one place
├── outputs.tf        # What Terraform prints after apply
├── network.tf        # VPC, subnets, IGW, route tables
├── security.tf       # Security groups and firewall rules
├── compute.tf        # EC2 instance and SSH key pair
├── database.tf       # RDS MySQL and DB subnet group
├── userdata.sh       # Bootstrap script template
└── .gitignore
```

**Why split into multiple files instead of one main.tf?**

In a real team nobody puts everything in one file. When something breaks at 2am you need to find the problem fast. Splitting by concern means:
- `network.tf` breaks → you look in `network.tf`
- Database won't connect → you look in `database.tf`
- App won't start → you look in `compute.tf` and `userdata.sh`

It also makes the codebase reusable. You can copy `database.tf` into a new project and adapt it without touching anything else.

---

## Step 1 — Create the Project and Branch

```bash
cd tf-aws-infrastructure
git checkout main
git pull
git checkout -b feat/epicbook-app
mkdir -p epicbook-app/docs
cd epicbook-app
touch main.tf variables.tf outputs.tf network.tf security.tf compute.tf database.tf userdata.sh .gitignore
code .
```

**Why branch first:**
Every project gets its own branch. Main always stays clean and deployable. If something goes wrong on the branch you can abandon it without breaking anything on main.

---

## Step 2 — variables.tf

This is always written first because every other file references variables. Define them once here and reference everywhere else.

```hcl
variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-west-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet where EC2 lives"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet where RDS lives"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_cidr_b" {
  description = "Second private subnet in a different AZ — required by RDS subnet group"
  type        = string
  default     = "10.0.3.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = "epicbook-key"
}

variable "db_name" {
  description = "Name of the MySQL database"
  type        = string
  default     = "bookstore"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "admin123"
}

variable "db_password" {
  description = "Master password for RDS"
  type        = string
  default     = "epicbook123!"
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance size"
  type        = string
  default     = "db.t3.micro"
}
```

**Key points:**

`sensitive = true` on the password — Terraform will never print it in logs or terminal output even with verbose flags. Critical for security.

`description` on every variable — this is documentation. Six months from now you or a teammate reads this and immediately understands what every variable is for.

The second private subnet `private_subnet_cidr_b` — RDS requires subnets in at least two availability zones for its subnet group. Even running a single RDS instance, AWS enforces this requirement.

---

## Step 3 — main.tf

```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "http" "my_ip" {
  url = "https://api.ipify.org"
}

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
```

**Why main.tf stays minimal:**

`main.tf` is the entry point, not the workhorse. It declares the Terraform version, provider, and shared data blocks every other file needs. Nothing else.

`required_version = ">= 1.0"` — protects against running on old Terraform versions with different syntax.

`~> 5.0` — pins to AWS provider major version 5. Prevents unexpected breaking changes if the provider auto-updates.

`owners = ["099720109477"]` — Canonical's official AWS account ID. Ensures you only get genuine Ubuntu images, not third-party AMIs impersonating Ubuntu.

The `data.http.my_ip` block hits `api.ipify.org` every time you run `terraform plan`. It returns your current public IP which gets used in the SSH security group rule. No manual IP updates ever.

---

## Step 4 — network.tf

```hcl
resource "aws_vpc" "epicbook_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "epicbook-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.epicbook_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "epicbook-public-subnet"
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.epicbook_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "epicbook-private-subnet-a"
  }
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.epicbook_vpc.id
  cidr_block        = var.private_subnet_cidr_b
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "epicbook-private-subnet-b"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.epicbook_vpc.id

  tags = {
    Name = "epicbook-igw"
  }
}

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

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}
```

**Breaking down every decision:**

`enable_dns_support = true` and `enable_dns_hostnames = true` on the VPC — RDS gives you a hostname like `epicbook-rds.abc123.us-west-1.rds.amazonaws.com`. Your app connects using that hostname. Without these two flags DNS resolution inside the VPC does not work and the app cannot find the database.

`map_public_ip_on_launch = true` on the public subnet — any EC2 launched here automatically gets a public IP. Without this you would need to manually assign one every time.

**Two private subnets in different availability zones** — AWS requires this for RDS subnet groups even if you're running a single database instance. `"${var.aws_region}a"` and `"${var.aws_region}b"` dynamically build the AZ names from your region variable.

**No route table for private subnets** — intentional. Private subnets use the VPC's default route table which only has local routes. There is literally no network path from the private subnets to the internet gateway. RDS physically cannot receive or send internet traffic.

→ **SS2** — AWS Console → VPC → Subnets. Show all three subnets with their CIDRs and the VPC they belong to.

---

## Step 5 — security.tf

```hcl
resource "aws_security_group" "ec2_sg" {
  name        = "epicbook-ec2-sg"
  description = "Allow SSH from my IP and HTTP from anywhere"
  vpc_id      = aws_vpc.epicbook_vpc.id

  tags = {
    Name = "epicbook-ec2-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_ssh" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "${chomp(data.http.my_ip.response_body)}/32"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ec2_http" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ec2_outbound" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "rds_sg" {
  name        = "epicbook-rds-sg"
  description = "Allow MySQL only from EC2 security group"
  vpc_id      = aws_vpc.epicbook_vpc.id

  tags = {
    Name = "epicbook-rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_mysql" {
  security_group_id            = aws_security_group.rds_sg.id
  referenced_security_group_id = aws_security_group.ec2_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rds_outbound" {
  security_group_id = aws_security_group.rds_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

**The most important security concept in this project:**

The RDS ingress rule uses `referenced_security_group_id` instead of `cidr_ipv4`. This is the difference between good and production-grade security.

Using a CIDR like `10.0.1.0/24` as the source means any machine in that IP range can reach the database. Using `referenced_security_group_id = aws_security_group.ec2_sg.id` means only resources that are members of the EC2 security group can reach the database. Even if someone launches another server in the same subnet with a different SG they cannot reach RDS. This is called least privilege and it is the production standard for database access.

`ip_protocol = "-1"` on egress means all protocols and all ports. Fine for outbound because you want EC2 to reach the internet, RDS, and anything else it needs.

→ **SS3** — AWS Console → EC2 → Security Groups → epicbook-ec2-sg → Inbound rules. Show SSH and HTTP ports with their sources.

→ **SS4** — AWS Console → EC2 → Security Groups → epicbook-rds-sg → Inbound rule. Show MySQL 3306 sourced from the EC2 SG name, not a CIDR.

---

## Step 6 — compute.tf

```hcl
resource "aws_key_pair" "epicbook_key" {
  key_name   = var.key_name
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "epicbook_ec2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  key_name                    = aws_key_pair.epicbook_key.key_name
  associate_public_ip_address = true

  user_data = templatefile("userdata.sh", {
    db_host     = aws_db_instance.epicbook_rds.address
    db_name     = var.db_name
    db_username = var.db_username
    db_password = var.db_password
    db_port     = 3306
    app_port    = 8080
  })

  tags = {
    Name = "epicbook-ec2"
  }
}
```

**Why `templatefile()` instead of `file()`:**

`file("userdata.sh")` reads the script as-is. It cannot inject dynamic values. `templatefile("userdata.sh", {...})` reads the script and replaces any `${variable}` placeholders with real values before passing it to EC2. This is how the RDS endpoint — which only exists after Terraform creates RDS — gets into the bootstrap script automatically.

Terraform sees that `compute.tf` references `aws_db_instance.epicbook_rds.address` and builds the dependency graph automatically. RDS is created first, its endpoint is captured, injected into the script, then EC2 is created. Zero manual steps.

→ **SS5** — AWS Console → EC2 → Instances → epicbook-ec2. Show the instance summary with public IP, subnet, and security group visible.

---

## Step 7 — database.tf

```hcl
resource "aws_db_subnet_group" "epicbook_db_subnet_group" {
  name       = "epicbook-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_subnet_a.id,
    aws_subnet.private_subnet_b.id
  ]

  tags = {
    Name = "epicbook-db-subnet-group"
  }
}

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

  timeouts {
    delete = "40m"
  }

  tags = {
    Name = "epicbook-rds"
  }
}
```

**Why every setting here matters:**

`db_subnet_group_name` — tells RDS which subnets it can use. Without this RDS goes into the default VPC which defeats the entire private subnet architecture.

`publicly_accessible = false` — non-negotiable. Makes RDS invisible to the internet. No public IP, no externally resolvable DNS name.

`skip_final_snapshot = true` — allows clean teardown in dev environments without blocking on a backup snapshot. In production set this to `false`.

`timeouts { delete = "40m" }` — RDS takes time to delete and AWS holds onto its network interfaces for several minutes afterward. Without this timeout Terraform gives up too early and tries to delete the VPC before RDS ENIs are released, causing a stuck destroy.

→ **SS6** — AWS Console → RDS → Databases → epicbook-rds. Show the instance summary with Publicly accessible: No clearly visible.

→ **SS7** — RDS → epicbook-rds → Connectivity & security tab. Show the VPC, subnet group, and RDS SG attached.

---

## Step 8 — outputs.tf

```hcl
output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.epicbook_ec2.public_ip
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint"
  value       = aws_db_instance.epicbook_rds.address
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = aws_db_instance.epicbook_rds.port
}

output "app_url" {
  description = "URL to access the EpicBook app"
  value       = "http://${aws_instance.epicbook_ec2.public_ip}"
}
```

Outputs are not just for printing. In larger Terraform setups one module's outputs become another module's inputs. Keeping them in a dedicated file makes it easy to see what this project exposes to the outside world.

---

## Step 9 — userdata.sh

This script runs automatically on EC2's first boot. Terraform passes the RDS endpoint and database credentials in via `templatefile()`. Every `${variable}` placeholder gets replaced with the real value before the script reaches the VM.

```bash
#!/bin/bash
set -e

apt-get update -y
apt-get upgrade -y
apt-get install -y nodejs npm git nginx mysql-client

cd /home/ubuntu
git clone https://github.com/0dow0ri7s3/theepicbook.git
cd theepicbook

cat > .env <<EOF
DB_HOST=${db_host}
DB_USER=${db_username}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
DB_PORT=${db_port}
PORT=${app_port}
EOF

cat > config/config.json <<EOF
{
  "development": {
    "username": "${db_username}",
    "password": "${db_password}",
    "database": "${db_name}",
    "host": "${db_host}",
    "dialect": "mysql"
  },
  "test": {
    "username": "root",
    "password": null,
    "database": "database_test",
    "host": "127.0.0.1",
    "dialect": "mysql"
  },
  "production": {
    "username": "${db_username}",
    "password": "${db_password}",
    "database": "${db_name}",
    "host": "${db_host}",
    "dialect": "mysql"
  }
}
EOF

npm install

echo "Waiting for RDS to be ready..."
for i in {1..30}; do
  if mysqladmin ping -h "${db_host}" -u "${db_username}" -p"${db_password}" --silent 2>/dev/null; then
    echo "RDS is ready"
    break
  fi
  echo "Attempt $i — waiting 10 seconds..."
  sleep 10
done

mysql -h "${db_host}" -u "${db_username}" -p"${db_password}" \
  -e "CREATE DATABASE IF NOT EXISTS ${db_name};"

mysql -h "${db_host}" -u "${db_username}" -p"${db_password}" "${db_name}" \
  < /home/ubuntu/theepicbook/db/BuyTheBook_Schema.sql

mysql -h "${db_host}" -u "${db_username}" -p"${db_password}" "${db_name}" \
  < /home/ubuntu/theepicbook/db/author_seed.sql

mysql -h "${db_host}" -u "${db_username}" -p"${db_password}" "${db_name}" \
  < /home/ubuntu/theepicbook/db/books_seed.sql

npm install -g pm2
sudo -u ubuntu bash -c "cd /home/ubuntu/theepicbook && pm2 start npm --name 'epicbook' -- start"
sudo -u ubuntu bash -c "pm2 save"
env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu
systemctl enable pm2-ubuntu

cat > /etc/nginx/sites-available/epicbook <<'NGINXCONF'
server {
  listen 80;
  server_name _;

  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/epicbook /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
systemctl enable nginx

echo "EpicBook deployment complete"
```

**Breaking down each section:**

`set -e` — stops the script immediately if any command fails. Without this the script keeps running after an error and leaves the server in a broken half-configured state.

`config/config.json overwrite` — the app hardcodes `127.0.0.1` as the database host in `config/config.json`. The `.env` file is completely ignored by this app. We overwrite `config.json` directly. This was discovered during debugging and is a critical fix.

`RDS wait loop` — RDS is provisioned by Terraform but takes additional time before it accepts connections. The loop retries every 10 seconds up to 30 times. Without it the script hits the database before it's ready and the SQL imports fail.

`sudo -u ubuntu` for PM2 — running PM2 as root causes the startup service to register as `pm2-undefined` instead of `pm2-ubuntu`. The app starts but fails to survive a reboot. Running as the `ubuntu` user fixes this permanently.

`<<'NGINXCONF'` with quotes around the delimiter — single quotes tell bash not to expand `$variables` inside that block. Without quotes bash tries to replace `$host`, `$remote_addr`, and `$proxy_add_x_forwarded_for` with shell variables that don't exist.

**Why Nginx as a reverse proxy:**

You cannot run Node on port 80 without root privileges which is a security risk. Nginx runs as a proper system service on port 80 and forwards traffic to your Node app on port 8080.

---

## Step 10 — Deploy

```bash
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

`terraform validate` — checks for syntax errors before you deploy. Always run this.

`terraform plan -out=tfplan` — saves the plan to a file. When you apply that saved plan Terraform executes exactly what was reviewed. No surprises.

RDS takes 10 to 15 minutes to provision. EC2 comes up faster but the bootstrap script needs another 5 to 10 minutes. Total wait is about 20 minutes.

→ **SS8** — terminal showing `terraform apply tfplan` output with all resources created and the outputs block printed at the bottom showing EC2 public IP and RDS endpoint.

---

## Step 11 — Verify the Deployment

**Check bootstrap script finished:**
```bash
ssh -i ~/.ssh/id_rsa ubuntu@<public_ip>
sudo tail -50 /var/log/cloud-init-output.log
```

Look for `EpicBook deployment complete` at the bottom.

**Check the app is running:**
```bash
pm2 status
```

Expected: `epicbook` process with status `online` and user `ubuntu`.

→ **SS9** — terminal showing `pm2 status` with epicbook online and ubuntu as the user.

**Check port 8080 is listening:**
```bash
ss -tulpn | grep 8080
```

**Check Nginx is running:**
```bash
sudo systemctl status nginx
```

**Check database connectivity and book count:**
```bash
mysql -h <rds_endpoint> -u admin123 -p \
  -e "USE bookstore; SELECT COUNT(*) FROM Book;"
```

→ **SS11** — terminal showing the MySQL query output returning the book count.

**Visit the app:**
```
http://<ec2_public_ip>
```

→ **SS10** — browser showing EpicBook app fully loaded with books displayed and the public IP visible in the address bar.

---

## Step 12 — Tear Down

```bash
terraform destroy
```

RDS takes 10 to 15 minutes to delete. The VPC deletion will appear stuck for several minutes afterward. This is normal. AWS holds RDS network interfaces for a few minutes after deletion before releasing them. The VPC cannot delete until all ENIs inside it are gone. Let it run.

---

## Troubleshooting

---

### App shows 502 Bad Gateway

Nginx is running but cannot reach Node on port 8080. The app either hasn't started or crashed.

**Diagnose:**
```bash
sudo tail -f /var/log/cloud-init-output.log
pm2 status
pm2 logs epicbook --lines 50
ss -tulpn | grep 8080
```

**Fix:**
```bash
cd /home/ubuntu/theepicbook
pm2 start npm --name "epicbook" -- start
```

---

### SequelizeConnectionRefusedError: connect ECONNREFUSED 127.0.0.1:3306

**What it means:** The app is connecting to localhost instead of RDS. It's ignoring `.env`.

**Why it happens:** The EpicBook app reads database config from `config/config.json` not `.env`. The original file hardcodes `127.0.0.1`.

**Diagnose:**
```bash
cat /home/ubuntu/theepicbook/config/config.json
pm2 logs epicbook --lines 50
```

**Fix manually:**
```bash
nano /home/ubuntu/theepicbook/config/config.json
# Update host in development and production to your RDS endpoint
pm2 restart epicbook
pm2 logs epicbook --lines 20
```

**Permanent fix:** `userdata.sh` now overwrites `config/config.json` automatically at deploy time.

---

### Error: listen EADDRINUSE: address already in use :::8080

**What it means:** A previous crashed PM2 process is still holding port 8080.

**Diagnose:**
```bash
ss -tulpn | grep 8080
pm2 logs epicbook --lines 30
```

**Fix:**
```bash
sudo fuser -k 8080/tcp
pm2 restart epicbook
```

---

### Books not showing on the app

**What it means:** App is connected to RDS but database is empty.

**Diagnose:**
```bash
mysql -h <rds_endpoint> -u admin123 -p \
  -e "USE bookstore; SELECT COUNT(*) FROM Book;"
```

**Fix:**
```bash
mysql -h <rds_endpoint> -u admin123 -p bookstore \
  < /home/ubuntu/theepicbook/db/BuyTheBook_Schema.sql

mysql -h <rds_endpoint> -u admin123 -p bookstore \
  < /home/ubuntu/theepicbook/db/author_seed.sql

mysql -h <rds_endpoint> -u admin123 -p bookstore \
  < /home/ubuntu/theepicbook/db/books_seed.sql

pm2 restart epicbook
```

**Root cause:** `db_name` was set to `epicbook` in Terraform config but the SQL dumps populate `bookstore`. Fixed in `variables.tf`.

---

### PM2 startup registers as pm2-undefined

**What it means:** PM2 started as root. Startup service registers as `pm2-undefined`. App dies on reboot.

**Diagnose:**
```bash
pm2 status
systemctl status pm2-ubuntu
```

**Fix manually:**
```bash
pm2 delete epicbook
sudo -u ubuntu bash -c "cd /home/ubuntu/theepicbook && pm2 start npm --name 'epicbook' -- start"
sudo -u ubuntu bash -c "pm2 save"
env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu
```

**Permanent fix:** `userdata.sh` now uses `sudo -u ubuntu` to start PM2.

---

### VPC stuck deleting for 10+ minutes

**What to do:** Nothing. Let it run. AWS is releasing RDS network interfaces. The VPC waits until all ENIs are fully gone. It will complete.

---

## Useful Commands Reference

```bash
# Check bootstrap script progress live
sudo tail -f /var/log/cloud-init-output.log

# Check full bootstrap log
sudo cat /var/log/cloud-init-output.log

# PM2 process status
pm2 status

# PM2 live logs
pm2 logs epicbook

# PM2 last 50 lines
pm2 logs epicbook --lines 50

# Restart app
pm2 restart epicbook

# Check what is listening on a port
ss -tulpn | grep 8080

# Kill a process on a port
sudo fuser -k 8080/tcp

# Check Nginx status
sudo systemctl status nginx

# Test Nginx config
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx

# View Nginx site config
cat /etc/nginx/sites-available/epicbook

# Connect to RDS from EC2
mysql -h <rds_endpoint> -u admin123 -p

# Check database tables
mysql -h <rds_endpoint> -u admin123 -p -e "USE bookstore; SHOW TABLES;"

# Count books in database
mysql -h <rds_endpoint> -u admin123 -p -e "USE bookstore; SELECT COUNT(*) FROM Book;"

# Test local app response
curl -I http://localhost:8080

# Test app through Nginx
curl -I http://localhost:80

# Check .env file
cat /home/ubuntu/theepicbook/.env

# Check config.json
cat /home/ubuntu/theepicbook/config/config.json
```
