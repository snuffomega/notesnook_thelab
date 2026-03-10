#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# Notesnook Backup Script
# Run manually or via Unraid User Scripts (Settings → User Scripts)
#
# Backs up:
#   - MongoDB (logical dump via mongodump)
#   - MinIO attachments (bind mount path)
#   - .env config file
#
# Restore: use scripts/restore.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APPDATA_DIR="/mnt/user/appdata/notesnook"
BACKUP_ROOT="/mnt/user/backups/notesnook"
DATE=$(date +%Y-%m-%d_%H-%M)
BACKUP_DIR="${BACKUP_ROOT}/${DATE}"
KEEP_DAYS=7   # daily backups to retain

echo "=== Notesnook Backup: ${DATE} ==="

# ── Preflight ──────────────────────────────────────────────────────────────────
if ! docker ps --format '{{.Names}}' | grep -q "^notesnook-db$"; then
  echo "ERROR: notesnook-db is not running. Start the stack before backing up."
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

# ── MongoDB logical dump ───────────────────────────────────────────────────────
echo "[1/3] Dumping MongoDB..."
docker exec notesnook-db mongodump --quiet --out /tmp/notesnook-backup
docker cp notesnook-db:/tmp/notesnook-backup "${BACKUP_DIR}/mongo-dump"
docker exec notesnook-db rm -rf /tmp/notesnook-backup
echo "      MongoDB dump → ${BACKUP_DIR}/mongo-dump"

# ── MinIO data ─────────────────────────────────────────────────────────────────
echo "[2/3] Backing up MinIO (S3) data..."
tar czf "${BACKUP_DIR}/s3data.tar.gz" -C "${APPDATA_DIR}" s3
echo "      MinIO backup → ${BACKUP_DIR}/s3data.tar.gz"

# ── Config ─────────────────────────────────────────────────────────────────────
echo "[3/3] Copying .env..."
cp "${APPDATA_DIR}/.env" "${BACKUP_DIR}/.env" 2>/dev/null || echo "      WARNING: .env not found at ${APPDATA_DIR}/.env"

# ── Prune old backups ──────────────────────────────────────────────────────────
echo "Pruning backups older than ${KEEP_DAYS} days..."
find "${BACKUP_ROOT}" -maxdepth 1 -type d -mtime "+${KEEP_DAYS}" -exec rm -rf {} + 2>/dev/null || true

echo "=== Backup complete: ${BACKUP_DIR} ==="
