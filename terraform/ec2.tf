# ---------- Upload Docker/Nginx config to S3 so bootstrap.sh can fetch it ----------
resource "aws_s3_object" "docker_compose" {
  bucket = aws_s3_bucket.backups.id
  key    = "app-config/docker-compose.yml"
  source = "${path.module}/../docker/docker-compose.yml"
  etag   = filemd5("${path.module}/../docker/docker-compose.yml")
}

resource "aws_s3_object" "nginx_conf" {
  bucket = aws_s3_bucket.backups.id
  key    = "app-config/nginx.conf"
  source = "${path.module}/../docker/nginx/nginx.conf"
  etag   = filemd5("${path.module}/../docker/nginx/nginx.conf")
}

# ---------- Latest Amazon Linux 2023 AMI ----------
data "aws_ami" "al2023_ec2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- Launch template ----------
resource "aws_launch_template" "wordpress" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.al2023_ec2.id
  instance_type = var.ec2_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(templatefile("${path.module}/../scripts/bootstrap.sh", {
    efs_id          = aws_efs_file_system.wordpress.id
    access_point_id = aws_efs_access_point.wordpress.id
    db_secret_arn   = aws_secretsmanager_secret.db_credentials.arn
    backup_bucket   = aws_s3_bucket.backups.id
    aws_region      = var.aws_region
  }))

  metadata_options {
    http_tokens = "required" # enforce IMDSv2, blocks a common SSRF-to-credential-theft path
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-wordpress"
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_s3_object.docker_compose,
    aws_s3_object.nginx_conf,
  ]
}
