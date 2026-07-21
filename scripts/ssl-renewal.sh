#!/bin/bash
set -euo pipefail

DOMAIN="${1:?Usage: ssl-renewal.sh <domain> <email>}"
EMAIL="${2:?Usage: ssl-renewal.sh <domain> <email>}"
WWW_PREFIX="www"
WWW_DOMAIN="${WWW_PREFIX}.${DOMAIN}"
CERT_DIR="/mnt/efs/certs"
LOCK_FILE="$CERT_DIR/.renewal.lock"

if [ -f "$LOCK_FILE" ] && [ $(($(date +%s) - $(stat -c %Y "$LOCK_FILE"))) -lt 300 ]; then
  echo "Another instance is renewing certs (lock < 5 min old). Skipping."
  exit 0
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

if ! command -v certbot &> /dev/null; then
  echo "Installing certbot..."
  python3 -m pip install --quiet certbot certbot-dns-route53
fi

mkdir -p "$CERT_DIR"

certbot certonly \
  --dns-route53 \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  --config-dir "$CERT_DIR" \
  --work-dir /tmp/certbot-work \
  --logs-dir /tmp/certbot-logs \
  -d "$DOMAIN" \
  -d "$WWW_DOMAIN"

echo "Certificate issued/renewed for $DOMAIN. Reloading nginx..."
docker exec nginx nginx -s reload || echo "Warning: nginx reload failed, container may not be running yet."

echo "=== SSL renewal complete: $(date) ==="
