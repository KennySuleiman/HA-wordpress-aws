#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/bootstrap.log) 2>&1

echo "=== Bootstrap started: $(date) ==="

# ---------- Variables injected by Terraform templatefile() ----------
EFS_ID="${efs_id}"
ACCESS_POINT_ID="${access_point_id}"
DB_SECRET_ARN="${db_secret_arn}"
BACKUP_BUCKET="${backup_bucket}"
AWS_REGION="${aws_region}"

# ---------- Install Docker ----------
dnf update -y
dnf install -y docker amazon-efs-utils jq

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Docker Compose plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# ---------- Mount EFS via access point ----------
mkdir -p /mnt/efs/wp-content
echo "$${EFS_ID}:/ /mnt/efs/wp-content efs _netdev,tls,accesspoint=$${ACCESS_POINT_ID} 0 0" >> /etc/fstab
mount -a -t efs

# ---------- Fetch DB credentials from Secrets Manager ----------
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$${DB_SECRET_ARN}" \
  --region "$${AWS_REGION}" \
  --query SecretString --output text)

DB_HOST=$(echo "$${SECRET_JSON}" | jq -r .host)
DB_NAME=$(echo "$${SECRET_JSON}" | jq -r .dbname)
DB_USER=$(echo "$${SECRET_JSON}" | jq -r .username)
DB_PASSWORD=$(echo "$${SECRET_JSON}" | jq -r .password)

# ---------- Pull app config from S3 and write the .env file ----------
mkdir -p /opt/wordpress
aws s3 cp "s3://$${BACKUP_BUCKET}/app-config/docker-compose.yml" /opt/wordpress/docker-compose.yml
mkdir -p /opt/wordpress/nginx
aws s3 cp "s3://$${BACKUP_BUCKET}/app-config/nginx.conf" /opt/wordpress/nginx/nginx.conf

cat > /opt/wordpress/.env << ENV
DB_HOST=$${DB_HOST}
DB_NAME=$${DB_NAME}
DB_USER=$${DB_USER}
DB_PASSWORD=$${DB_PASSWORD}
ENV
chmod 600 /opt/wordpress/.env

# ---------- Start containers ----------
cd /opt/wordpress
docker compose --env-file .env up -d

# ---------- CloudWatch agent ----------
dnf install -y amazon-cloudwatch-agent
# Full agent config (log groups, custom metrics) is provisioned in Phase 10.
# For now, this installs the agent so it's ready to be configured/started.

echo "=== Bootstrap finished: $(date) ==="
