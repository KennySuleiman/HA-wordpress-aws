#!/bin/bash
set -euo pipefail

BACKUP_BUCKET="${1:?Usage: restore.sh <bucket> <db-secret-arn> <aws-region> <db-backup-key|skip> <files-backup-key|skip>}"
DB_SECRET_ARN="${2:?}"
AWS_REGION="${3:?}"
DB_BACKUP_KEY="${4:?Pass an S3 key like backups/database/db-20260722-030000.sql.gz, or 'skip'}"
FILES_BACKUP_KEY="${5:?Pass an S3 key like backups/files/wp-content-20260722-030000.tar.gz, or 'skip'}"

WORK_DIR="/tmp/wp-restore-$(date +%s)"
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== Restore started: $(date) ==="
echo "This will overwrite the current database and/or wp-content. Ctrl+C within 10s to abort."
sleep 10

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$DB_SECRET_ARN" \
  --region "$AWS_REGION" \
  --query SecretString --output text)

DB_HOST=$(echo "$SECRET_JSON" | jq -r .host)
DB_NAME=$(echo "$SECRET_JSON" | jq -r .dbname)
DB_USER=$(echo "$SECRET_JSON" | jq -r .username)
DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r .password)

if [ "$DB_BACKUP_KEY" != "skip" ]; then
  echo "Restoring database from ${DB_BACKUP_KEY}..."
  aws s3 cp "s3://${BACKUP_BUCKET}/${DB_BACKUP_KEY}" "${WORK_DIR}/db-restore.sql.gz"
  gunzip "${WORK_DIR}/db-restore.sql.gz"
  docker exec -i wordpress sh -c \
    "mysql -h '${DB_HOST}' -u '${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}'" \
    < "${WORK_DIR}/db-restore.sql"
  echo "Database restore complete."
else
  echo "Skipping database restore."
fi

if [ "$FILES_BACKUP_KEY" != "skip" ]; then
  echo "Restoring wp-content from ${FILES_BACKUP_KEY}..."
  aws s3 cp "s3://${BACKUP_BUCKET}/${FILES_BACKUP_KEY}" "${WORK_DIR}/wp-content-restore.tar.gz"
  # Extract to a temp location first, then swap in — avoids a half-extracted
  # wp-content being served mid-restore, since /mnt/efs is live and shared
  # across every running instance.
  mkdir -p "${WORK_DIR}/extracted"
  tar -xzf "${WORK_DIR}/wp-content-restore.tar.gz" -C "${WORK_DIR}/extracted"
  rsync -a --delete "${WORK_DIR}/extracted/wp-content/" /mnt/efs/wp-content/
  echo "Files restore complete."
else
  echo "Skipping files restore."
fi

echo "=== Restore finished: $(date) ==="
