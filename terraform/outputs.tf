
output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "nat_instance_id" {
  value = aws_instance.nat.id
}

output "nat_public_ip" {
  value = aws_eip.nat.public_ip
}
