#!/bin/bash
set -euo pipefail

BACKUP_BUCKET="${1:?Usage: backup.sh <bucket> <db-secret-arn> <aws-region>}"
DB_SECRET_ARN="${2:?Usage: backup.sh <bucket> <db-secret-arn> <aws-region>}"
AWS_REGION="${3:?Usage: backup.sh <bucket> <db-secret-arn> <aws-region>}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOCK_FILE="/mnt/efs/.backup.lock"
WORK_DIR="/tmp/wp-backup-${TIMESTAMP}"

# Cross-instance lock, same pattern as ssl-renewal.sh — only one instance
# should run a backup at a time since both read from the same EFS/RDS.
if [ -f "$LOCK_FILE" ] && [ $(($(date +%s) - $(stat -c %Y "$LOCK_FILE"))) -lt 1800 ]; then
  echo "Another instance is backing up (lock < 30 min old). Skipping."
  exit 0
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR"
echo "=== Backup started: $(date) ==="

# ---------- Database dump ----------
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$DB_SECRET_ARN" \
  --region "$AWS_REGION" \
  --query SecretString --output text)

DB_HOST=$(echo "$SECRET_JSON" | jq -r .host)
DB_NAME=$(echo "$SECRET_JSON" | jq -r .dbname)
DB_USER=$(echo "$SECRET_JSON" | jq -r .username)
DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r .password)

echo "Dumping database..."
docker exec wordpress sh -c \
  "mysqldump -h '${DB_HOST}' -u '${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}'" \
  > "${WORK_DIR}/db-${TIMESTAMP}.sql"
gzip "${WORK_DIR}/db-${TIMESTAMP}.sql"

# ---------- WordPress files (wp-content) ----------
echo "Archiving wp-content..."
tar -czf "${WORK_DIR}/wp-content-${TIMESTAMP}.tar.gz" -C /mnt/efs wp-content

# ---------- Upload to S3 ----------
echo "Uploading to S3..."
aws s3 cp "${WORK_DIR}/db-${TIMESTAMP}.sql.gz" \
  "s3://${BACKUP_BUCKET}/backups/database/db-${TIMESTAMP}.sql.gz"
aws s3 cp "${WORK_DIR}/wp-content-${TIMESTAMP}.tar.gz" \
  "s3://${BACKUP_BUCKET}/backups/files/wp-content-${TIMESTAMP}.tar.gz"

echo "=== Backup finished: $(date) ==="
echo "DB backup:    s3://${BACKUP_BUCKET}/backups/database/db-${TIMESTAMP}.sql.gz"
echo "Files backup: s3://${BACKUP_BUCKET}/backups/files/wp-content-${TIMESTAMP}.tar.gz"
