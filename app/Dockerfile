# ── Build Stage ────────────────────────────────────────────────────────────────
FROM node:24 AS builder

WORKDIR /app

# Install git
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

# Pin to a specific Notesnook release for reproducible builds
# Override at build time: docker compose build --build-arg NOTESNOOK_VERSION=v3.x.x
ARG NOTESNOOK_VERSION=v3.3.8
RUN git clone --depth=1 --branch ${NOTESNOOK_VERSION} https://github.com/streetwriters/notesnook.git .

# Install monorepo dependencies
RUN npm ci

# Accept build-time URLs (baked into the React bundle — must rebuild if URLs change)
ARG NN_API_HOST
ARG NN_AUTH_HOST
ARG NN_SSE_HOST
ARG NN_MONOGRAPH_HOST

ENV NN_API_HOST=${NN_API_HOST}
ENV NN_AUTH_HOST=${NN_AUTH_HOST}
ENV NN_SSE_HOST=${NN_SSE_HOST}
ENV NN_MONOGRAPH_HOST=${NN_MONOGRAPH_HOST}

# Build the web app only
RUN npm run build:web

# ── Production Stage ───────────────────────────────────────────────────────────
FROM nginx

# Remove default nginx site
RUN rm -rf /usr/share/nginx/html/*

# Copy built React app
COPY --from=builder /app/apps/web/build /usr/share/nginx/html

# Custom nginx config (SPA routing + CSP with worker-src fix)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
