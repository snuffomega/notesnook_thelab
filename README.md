# Notesnook — Self-Hosted Stack

A complete self-hosted [Notesnook](https://notesnook.com) deployment. All data stays on your server; notes are end-to-end encrypted on your devices. This is a custom stack built on the official Streetwriters backend images with a locally-built web frontend.

## Services

| Container | Image | Host Port | Purpose |
|---|---|---|---|
| `notesnook-db` | `mongo:7.0.14` | — | MongoDB (user accounts, 2FA, sync metadata) |
| `notesnook-s3` | `minio/minio` | `9000` | S3-compatible attachment storage |
| `setup-s3` | `minio/mc` | — | One-time bucket creation (run-once) |
| `identity-server` | `streetwriters/identity:latest` | `8264` | Authentication / 2FA |
| `notesnook-server` | `streetwriters/notesnook-sync:latest` | `5264` | Sync API |
| `sse-server` | `streetwriters/sse:latest` | `7264` | Real-time updates |
| `monograph-server` | `streetwriters/monograph:latest` | `6264` | Public note sharing |
| `autoheal` | `willfarrell/autoheal:latest` | — | Auto-restart unhealthy containers |
| `app` | `thelab/notesnook-web` (local build) | `3010` | React web UI (nginx) |

---

## Prerequisites

- Unraid with Docker Compose v2
- A domain with DNS managed (Cloudflare recommended)
- An SMTP account (Gmail app password works)
- A reverse proxy / tunnel in front — see [External Access](#external-access)

---

## Setup

### 1. Clone the repo

```bash
git clone <REPO_URL> /mnt/user/appdata/notesnook
cd /mnt/user/appdata/notesnook
```

The `db/` and `s3/` directories are included in the repo so they're ready immediately. MongoDB and MinIO data is stored directly on the Unraid array — not inside `docker.img` — so data survives Docker crashes.

### 2. Copy and fill `.env`

```bash
cp example.env .env
nano .env
```

Minimum required fields:

| Variable | Description |
|---|---|
| `BASE_DOMAIN` | Your root domain |
| `INSTANCE_NAME` | Name shown in Notesnook apps |
| `NOTESNOOK_API_SECRET` | Random secret: `openssl rand -base64 32` |
| `SMTP_*` | Email credentials (for password reset, 2FA) |
| `MINIO_ROOT_PASSWORD` | MinIO password: `openssl rand -base64 12` |

Everything else is derived from `BASE_DOMAIN` automatically.

### 3. Build and start

```bash
# Build the web app from source (takes 2-5 minutes on first build)
docker compose build

# Start the full stack
docker compose up -d
```

### 4. Create your account

Access the web UI at `http://unraid-ip:3010` and create your first account.

> On first run MongoDB initialises its replica set — allow ~60s for all services to become healthy. Check: `docker compose ps`

---

## External Access

The stack exposes host ports that any router can point to. **The stack itself doesn't care what's in front of it.**

### Service → Port Map

| Subdomain | Service | Host Port |
|---|---|---|
| `notes.yourdomain.com` | `app` (web UI) | `3010` |
| `auth.yourdomain.com` | `identity-server` | `8264` |
| `sync.yourdomain.com` | `notesnook-server` | `5264` |
| `sse.yourdomain.com` | `sse-server` | `7264` |
| `mono.yourdomain.com` | `monograph-server` | `6264` |
| `s3.yourdomain.com` | `notesnook-s3` | `9000` |

### Option A — Different Docker network (ip:port)

Point your router at `http://UNRAID_IP:PORT` for each service.

**Pangolin example** — create a resource in the Pangolin dashboard for each:
- `notes.yourdomain.com` → `http://10.10.1.X:3010`
- `auth.yourdomain.com` → `http://10.10.1.X:8264`
- `sync.yourdomain.com` → `http://10.10.1.X:5264`
- `sse.yourdomain.com` → `http://10.10.1.X:7264`
- `mono.yourdomain.com` → `http://10.10.1.X:6264`
- `s3.yourdomain.com` → `http://10.10.1.X:9000`

Works the same for Traefik, Nginx Proxy Manager, Cloudflare Tunnel, etc.

### Option B — Same Docker network (container name)

If your router runs on the same host, add its network to `docker-compose.yml`:

```yaml
networks:
  notesnook:
    name: notesnook
    driver: bridge
  your-router-network:       # e.g. pangolin, traefik
    external: true
```

Then add `your-router-network` to each service that needs external exposure, and point your router at `http://app:80`, `http://notesnook-server:5264`, etc.

---

## Backup & Restore

MongoDB and MinIO are bind-mounted to `/mnt/user/appdata/notesnook/` so they survive Docker crashes. For additional protection, run scheduled backups.

### Backup

```bash
bash scripts/backup.sh
```

Saves to `/mnt/user/backups/notesnook/YYYY-MM-DD_HH-MM/`:
- `mongo-dump/` — logical MongoDB dump (accounts, 2FA, sync metadata)
- `s3data.tar.gz` — MinIO attachments archive
- `.env` — config snapshot

Keeps 7 days of daily backups automatically. Schedule via Unraid User Scripts (Settings → User Scripts → add as cron).

### Restore

```bash
bash scripts/restore.sh /mnt/user/backups/notesnook/2026-01-01_03-00
```

The restore script stops the stack, restores MinIO data, runs `mongorestore` against MongoDB, then restarts everything.

> After a restore, users need to log back in. 2FA tokens regenerate on next login.

---

## Updating

### Update backend images

```bash
docker compose pull
docker compose up -d
```

### Update the web app (new Notesnook release)

1. Update `NOTESNOOK_VERSION` in `.env` (check [releases](https://github.com/streetwriters/notesnook/releases))
2. Rebuild:

```bash
docker compose build --no-cache app
docker compose up -d app
```

> URLs are baked in at build time. If any `NN_*` or `*_PUBLIC_URL` values change, rebuild the `app` service.

### Update MongoDB / MinIO

Update the pinned tag in `docker-compose.yml`, then:

```bash
docker compose pull notesnook-db notesnook-s3
docker compose up -d notesnook-db notesnook-s3
```

---

## Common Commands

```bash
docker compose ps                              # status of all services
docker compose logs -f                         # tail all logs
docker compose logs -f notesnook-server        # tail one service
docker compose down                            # stop stack
docker compose build --no-cache app            # rebuild web app
```

---

## Troubleshooting

**Monograph unhealthy / "Connection refused"**
Bun server must bind to all interfaces. Both `HOST: 0.0.0.0` and `HOSTNAME: 0.0.0.0` are set in `docker-compose.yml`. Check logs: `docker compose logs monograph-server`

**"SharedService closed" / stuck on "Decrypting your notes"**
CSP `worker-src` issue. The `app/nginx.conf` includes the fix. If it persists after rebuild, clear browser site data for the domain (Settings → Clear site data).

**MongoDB unhealthy on first boot**
Replica set init takes ~60s. The healthcheck runs `rs.initiate()` automatically. If still unhealthy after 2 minutes: `docker compose restart notesnook-db`

**Web app using wrong server URLs**
Build args are baked in. Verify: `docker exec app grep -o 'NN_API_HOST[^"]*' /usr/share/nginx/html/index.html`
If wrong: update `.env` then `docker compose build --no-cache app && docker compose up -d app`

**MinIO "attachments" bucket missing**
Re-run setup: `docker compose run --rm setup-s3`
