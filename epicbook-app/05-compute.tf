
#=====================================================================
# SSH KEY PAIR
# #=====================================================================

resource "aws_key_pair" "epicbook_key" {
  key_name   = var.key_name
  public_key = file("~/.ssh/id_rsa.pub")
}

#=====================================================================
#          EC2 INSTANCE
#=====================================================================

resource "aws_instance" "epicbook_ec2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  key_name                    = aws_key_pair.epicbook_key.key_name
  associate_public_ip_address = true

  user_data = templatefile("07-userdata.sh", {
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