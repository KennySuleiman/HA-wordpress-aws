#!/bin/bash
set -euo pipefail

BACKUP_BUCKET="${1:?Usage: deploy.sh <bucket> <deployment-s3-key>}"
DEPLOY_KEY="${2:?Usage: deploy.sh <bucket> <deployment-s3-key>}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ROLLBACK_DIR="/mnt/efs/.deploy-backups/${TIMESTAMP}"
WORK_DIR="/tmp/deploy-${TIMESTAMP}"

mkdir -p "$WORK_DIR" "$ROLLBACK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== Deploy started: $(date) ==="

echo "Backing up current themes/plugins to ${ROLLBACK_DIR}..."
cp -r /mnt/efs/wp-content/themes "${ROLLBACK_DIR}/themes" 2>/dev/null || true
cp -r /mnt/efs/wp-content/plugins "${ROLLBACK_DIR}/plugins" 2>/dev/null || true
echo "${ROLLBACK_DIR}" > /mnt/efs/.last-deploy-backup

echo "Downloading deployment package..."
aws s3 cp "s3://${BACKUP_BUCKET}/${DEPLOY_KEY}" "${WORK_DIR}/deploy.tar.gz"

echo "Extracting..."
mkdir -p "${WORK_DIR}/extracted"
tar -xzf "${WORK_DIR}/deploy.tar.gz" -C "${WORK_DIR}/extracted"

echo "Syncing to EFS..."
rsync -a "${WORK_DIR}/extracted/themes/" /mnt/efs/wp-content/themes/ 2>/dev/null || true
rsync -a "${WORK_DIR}/extracted/plugins/" /mnt/efs/wp-content/plugins/ 2>/dev/null || true

# Fix ownership to match the access point's expected UID/GID (33, www-data)
chown -R 33:33 /mnt/efs/wp-content/themes /mnt/efs/wp-content/plugins

echo "=== Deploy finished: $(date) ==="
echo "Rollback point saved at: ${ROLLBACK_DIR}"
