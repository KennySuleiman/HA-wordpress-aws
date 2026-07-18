
output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "nat_instance_id" {
  value = aws_instance.nat.id
}

output "nat_public_ip" {
  value = aws_eip.nat.public_ip
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "ec2_sg_id" {
  value = aws_security_group.ec2.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}

output "efs_sg_id" {
  value = aws_security_group.efs.id
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "efs_file_system_id" {
  value = aws_efs_file_system.wordpress.id
}

output "efs_access_point_id" {
  value = aws_efs_access_point.wordpress.id
}

output "ec2_instance_profile_name" {
  value = aws_iam_instance_profile.ec2.name
}

output "backup_bucket_name" {
  value = aws_s3_bucket.backups.id
}
