#!/bin/bash
set -euo pipefail

echo "=== Rollback started: $(date) ==="

if [ ! -f /mnt/efs/.last-deploy-backup ]; then
  echo "No previous deployment backup found. Cannot roll back."
  exit 1
fi

ROLLBACK_DIR=$(cat /mnt/efs/.last-deploy-backup)

if [ ! -d "$ROLLBACK_DIR" ]; then
  echo "Backup directory ${ROLLBACK_DIR} no longer exists. Cannot roll back."
  exit 1
fi

echo "Restoring themes/plugins from ${ROLLBACK_DIR}..."
rsync -a --delete "${ROLLBACK_DIR}/themes/" /mnt/efs/wp-content/themes/ 2>/dev/null || true
rsync -a --delete "${ROLLBACK_DIR}/plugins/" /mnt/efs/wp-content/plugins/ 2>/dev/null || true

chown -R 33:33 /mnt/efs/wp-content/themes /mnt/efs/wp-content/plugins

echo "=== Rollback finished: $(date) ==="
