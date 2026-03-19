# Walkthrough — AWS Linux VM

A step-by-step guide to provisioning a Linux VM on AWS using Terraform. Covers everything from installing the tools to SSHing into a running VM with Nginx served over a public IP.

---

## Stack

- Terraform
- AWS CLI
- AWS (us-east-1)
- Ubuntu 22.04 LTS
- Nginx

---

## Step 1 — Install AWS CLI

Download and install from the official page:
```
https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
```

Verify it worked:
```bash
aws --version
```

---

## Step 2 — Configure AWS CLI

```bash
aws configure
```

Enter your:
- AWS Access Key ID
- AWS Secret Access Key
- Default region: `us-east-1`
- Default output format: `json`

---

## Step 3 — Create the Project Folder

```bash
mkdir tf-aws-infrastructure
cd tf-aws-infrastructure
mkdir linux-vm
cd linux-vm
code .
```

Create your main config file:
```bash
touch main.tf
touch userdata.sh
```

---

## Step 4 — Configure the AWS Provider

Add to `main.tf`:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

This tells Terraform to use the AWS provider and deploy resources in `us-east-1`.

---

## Step 5 — Create the VPC

```hcl
resource "aws_vpc" "terraform-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "terraform-vpc"
  }
}
```

The VPC is your private network on AWS. Everything you build lives inside it.

---

## Step 6 — Create the Public Subnet

```hcl
resource "aws_subnet" "terraform-sub" {
  vpc_id     = aws_vpc.terraform-vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "terraform-sub"
  }
}
```

Your EC2 instance lives in this subnet. The `/24` gives you 254 usable IPs.

---

## Step 7 — Create the Private Subnet

```hcl
resource "aws_subnet" "terraform-sub-private" {
  vpc_id     = aws_vpc.terraform-vpc.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "terraform-sub-private"
  }
}
```

No internet access. Reserved for databases or internal services.

---

## Step 8 — Create the Internet Gateway

```hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.terraform-vpc.id

  tags = {
    Name = "terraform-igw"
  }
}
```

The IGW is what connects your VPC to the internet. Without it, nothing inside the VPC can reach the outside world.

---

## Step 9 — Create the Route Table

```hcl
resource "aws_route_table" "terraform-rt" {
  vpc_id = aws_vpc.terraform-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "terraform-rt"
  }
}
```

Tells the VPC to send all external traffic (`0.0.0.0/0`) through the IGW. AWS handles internal VPC routing automatically.

---

## Step 10 — Associate Route Table to Public Subnet

```hcl
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.terraform-sub.id
  route_table_id = aws_route_table.terraform-rt.id
}
```

Creating the route table alone is not enough. This block actually attaches it to the public subnet.

---

## Step 11 — Create the Security Group

```hcl
resource "aws_security_group" "terraform-sg" {
  name        = "terraform-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.terraform-vpc.id

  tags = {
    Name = "terraform-sg"
  }
}
```

The security group acts as a firewall for your EC2 instance.

---

## Step 12 — Fetch Your Public IP Dynamically

```hcl
data "http" "my_ip" {
  url = "https://api.ipify.org"
}
```

Fetches your current public IP at plan time. Eliminates manual IP updates when your IP changes.

---

## Step 13 — Add Inbound Rules

```hcl
resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id = aws_security_group.terraform-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.terraform-sg.id
  cidr_ipv4         = "${chomp(data.http.my_ip.response_body)}/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}
```

HTTP open to everyone. SSH locked to your IP only. The `chomp()` strips any trailing newline from the IP response.

---

## Step 14 — Add Outbound Rule

```hcl
resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.terraform-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

AWS blocks all outbound traffic by default. Without this rule the VM cannot reach the internet to download packages. `ip_protocol = "-1"` means all protocols and ports.

---

## Step 15 — Register SSH Key Pair

```hcl
resource "aws_key_pair" "terraform-key" {
  key_name   = "terraform-key"
  public_key = file("~/.ssh/id_rsa.pub")
}
```

Registers your local public key with AWS so it gets injected into the VM at creation time.

Generate the key if you don't have one:
```bash
ssh-keygen -t rsa -b 4096
```

---

## Step 16 — Create the AMI Data Source

```hcl
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

Dynamically fetches the latest Ubuntu 22.04 AMI ID from Canonical. Avoids hardcoding an AMI ID that can go stale.

---

## Step 17 — Create the EC2 Instance

```hcl
resource "aws_instance" "terraform-vm" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.terraform-sub.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.terraform-sg.id]
  key_name                    = aws_key_pair.terraform-key.key_name
  user_data                   = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl start nginx
    systemctl enable nginx
  EOF

  tags = {
    Name = "terraform-aws-vm"
  }
}
```

`associate_public_ip_address = true` is required — not automatic. `user_data` runs the bootstrap script on first boot.

---

## Step 18 — Output the Public IP

```hcl
output "public_ip" {
  value = aws_instance.terraform-vm.public_ip
}
```

Prints the public IP after apply so you don't have to hunt for it in the AWS console.

---

## Step 19 — Generate SSH Key

```bash
ssh-keygen -t rsa -b 4096
```

Hit Enter through all prompts. Keys save to `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`.

Verify:
```bash
ls ~/.ssh/
```

---

## Step 20 — Create userdata.sh

In the project root create `userdata.sh`:

```bash
#!/bin/bash
apt-get update -y
apt-get install -y nginx
systemctl start nginx
systemctl enable nginx
```

The `#!/bin/bash` shebang on the first line is not optional. Cloud-init uses it to identify the file as a shell script. Without it the script is ignored silently.

---

## Step 21 — Run Terraform

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

After apply the public IP prints to terminal. Paste it in a browser — Nginx default page confirms everything worked.

---

## Step 22 — SSH Into the VM

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<public_ip>
```

Note: AWS Ubuntu instances use `ubuntu` as the username, not `adminuser`.

---

## Step 23 — Verify Nginx

```bash
systemctl status nginx
```

Should show `active (running)`.

---

## Step 24 — Tear Down

```bash
terraform destroy
```

Removes everything Terraform created in AWS.

---

## Troubleshooting

### AMI data source not declared

```
A data resource "aws_ami" "ubuntu" has not been declared
```

The AMI data block was missing from `main.tf`. Add the `data "aws_ami" "ubuntu"` block before the EC2 resource block.

---

### Subnet reference not found

```
A managed resource "aws_subnet" "terraform-subnet" has not been declared
```

Resource name mismatch. The subnet was declared as `terraform-sub` but referenced as `terraform-subnet` in the EC2 block. Always match the reference name to the declared resource name exactly.

---

### Route table destination error

```
InvalidParameterValue: The destination CIDR block 10.0.1.0/24 is equal to or more specific than one of this VPC's CIDR blocks
```

The route table was pointing to the subnet's own CIDR instead of `0.0.0.0/0`. Internal VPC routing is handled automatically. The IGW route should always be `0.0.0.0/0`.

---

### Security group invalid address prefix

The `from_port` was set to `"*"` which is invalid. AWS expects a port number. Set `from_port` and `to_port` to the same value for single-port rules.

---

### userdata not running on boot

```
Unhandled non-multipart (text/x-not-multipart) userdata
```

Cloud-init received the script but couldn't process it. Two possible causes. First, missing `#!/bin/bash` shebang on the first line. Second, passing the script via `file()` instead of an inline heredoc. Switch to heredoc syntax in the `user_data` block.

Check cloud-init logs on the VM:
```bash
sudo cat /var/log/cloud-init-output.log
```

---

### VM has no outbound internet access

Nginx failed to install because the VM couldn't reach the internet. AWS security groups block all outbound traffic by default unless an explicit egress rule is added. Add `aws_vpc_security_group_egress_rule` with `ip_protocol = "-1"` to allow all outbound traffic.

---

### SSH connection timed out

```
ssh: connect to host x.x.x.x port 22: Connection timed out
```

Two possible causes. Your IP changed since the security group rule was written — run `curl ifconfig.me` and compare. Or the security group was never attached to the EC2 instance — confirm `vpc_security_group_ids` is set in the instance block.

---

### file() path error for SSH public key

```
Invalid value for "path" parameter: no file exists at "~/.ssh/id_rsa.pub"
```

On Windows, Terraform doesn't always resolve `~` correctly. Use the full absolute path:
```hcl
public_key = file("C:/Users/DELL/.ssh/id_rsa.pub")
```

---

## Notes

- AWS calls bootstrap scripts `user_data`, Azure calls them `custom_data` — same concept, different name
- Always use `terraform plan -out=tfplan` before applying — it locks in exactly what gets deployed
- `chomp()` is important when using dynamic IP fetching — strips trailing newlines that would break CIDR notation
- `t2.micro` is free tier eligible — good for learning and testing
- Destroy resources when done to avoid unexpected AWS charges
