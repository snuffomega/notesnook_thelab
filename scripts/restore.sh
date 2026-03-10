#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# Notesnook Restore Script
# Usage: ./restore.sh /mnt/user/backups/notesnook/2026-01-01_03-00
#
# Restores:
#   - MongoDB from mongodump
#   - MinIO attachments from tar archive
#
# WARNING: This OVERWRITES existing data. Stop all clients before restoring.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APPDATA_DIR="/mnt/user/appdata/notesnook"
COMPOSE_DIR="/mnt/user/appdata/notesnook"   # where docker-compose.yml lives

# ── Args ───────────────────────────────────────────────────────────────────────
if [ -z "${1:-}" ]; then
  echo "Usage: $0 <backup-dir>"
  echo "Example: $0 /mnt/user/backups/notesnook/2026-01-01_03-00"
  exit 1
fi

BACKUP_DIR="$1"

if [ ! -d "${BACKUP_DIR}" ]; then
  echo "ERROR: Backup directory not found: ${BACKUP_DIR}"
  exit 1
fi

echo "=== Notesnook Restore from: ${BACKUP_DIR} ==="
echo "WARNING: This will OVERWRITE current data. Press Ctrl+C within 5s to cancel."
sleep 5

# ── Stop stack ─────────────────────────────────────────────────────────────────
echo "[1/4] Stopping stack..."
cd "${COMPOSE_DIR}"
docker compose down

# ── Restore MinIO ─────────────────────────────────────────────────────────────
if [ -f "${BACKUP_DIR}/s3data.tar.gz" ]; then
  echo "[2/4] Restoring MinIO data..."
  rm -rf "${APPDATA_DIR}/s3"
  tar xzf "${BACKUP_DIR}/s3data.tar.gz" -C "${APPDATA_DIR}"
  echo "      MinIO restored."
else
  echo "[2/4] WARNING: No s3data.tar.gz found — skipping MinIO restore."
fi

# ── Start DB only, restore, then full stack ────────────────────────────────────
echo "[3/4] Starting MongoDB for restore..."
docker compose up -d notesnook-db
echo "      Waiting for MongoDB to be ready..."
sleep 15

if [ -d "${BACKUP_DIR}/mongo-dump" ]; then
  echo "      Restoring MongoDB from dump..."
  docker cp "${BACKUP_DIR}/mongo-dump" notesnook-db:/tmp/notesnook-restore
  docker exec notesnook-db mongorestore --drop /tmp/notesnook-restore
  docker exec notesnook-db rm -rf /tmp/notesnook-restore
  echo "      MongoDB restored."
else
  echo "      WARNING: No mongo-dump directory found — skipping MongoDB restore."
fi

# ── Start full stack ───────────────────────────────────────────────────────────
echo "[4/4] Starting full stack..."
docker compose up -d

echo "=== Restore complete. Stack is starting up. ==="
echo "    Allow ~60s for all services to become healthy."
echo "    Check status: docker compose ps"
