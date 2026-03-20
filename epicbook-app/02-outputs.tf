output "ec2_public_ip" {
  description = "Public IP of the EC2 instance — use this to SSH and visit the app"
  value       = aws_instance.epicbook_ec2.public_ip
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint — used by the app to connect to the database"
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