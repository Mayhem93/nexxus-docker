# syntax=docker/dockerfile:1
#
# Nexxus Transport Manager Worker — pluggable base image
# -----------------------------------------------------------------------------
# This is a BASE image. It contains the compiled nexxus transport manager worker but NO config.
# Downstream deployments:
#   1. `FROM` this image,
#   2. supply a config at $NXX_CONF_PATH (COPY in a child image, or bind-mount
#      at runtime),
#   3. `npm install` any custom adapter packages named in that config,
#   4. set the ENV vars their config requires.
#
# Build:
#   docker build -t <registry>/nexxus-worker-transport-manager:latest ./worker-transport-manager
# -----------------------------------------------------------------------------

# ---- Global build arguments (override with --build-arg) ----------------------
# The nexxus-worker-transport-manager repo + release are intentionally NOT build-args
# (this image's version is coupled to one nexxus-worker-transport-manager release) —
# see NEXXUS_WORKER_ARCHIVE_URL in the builder stage for the single, private-mirror override.
# ARG NODE_VERSION=24
ARG INSTALL_DIR=/usr/local/nexxus-worker-transport-manager
ARG NXX_CONF_PATH=/etc/nexxus/worker-transport-manager.conf.json

# =============================================================================
# Stage 1 — builder: fetch source at the tag, compile TS, prune to prod deps.
# Everything here is discarded; the final image inherits none of it (no git,
# no tarball, no dev dependencies, no source .ts files).
# =============================================================================
FROM node:24-alpine AS builder

ARG INSTALL_DIR

# Source archive for THIS image. The repo + tag are intentionally fixed here
# (not build-args): the image version tracks a specific nexxus-worker-transport-manager
# release — bump this URL and the version LABEL together when cutting a new image.
# Override ONLY to build from a private / closed-source mirror, e.g.:
#   --build-arg NEXXUS_WORKER_ARCHIVE_URL=https://<host>/<path>.tar.gz
# Caveat: ADD can't send auth headers, so a private URL must already be
# authenticated (e.g. a signed URL). Token-auth fetches need a secret mount:
#   RUN --mount=type=secret,id=token wget --header=... -O /tmp/src.tgz <url>
ARG NEXXUS_WORKER_ARCHIVE_URL=https://github.com/Mayhem93/nexxus-worker-transport-manager/archive/refs/tags/0.0.2.tar.gz

WORKDIR ${INSTALL_DIR}

# Fetch the source tarball — no git binary anywhere.
# NOTE: ADD does NOT auto-extract *remote* tarballs, so we extract explicitly.
# --strip-components=1 drops the single "<repo>-<ref>/" top-level directory
# (works regardless of the archive's top-level folder name).
ADD ${NEXXUS_WORKER_ARCHIVE_URL} /tmp/src.tgz
RUN tar -xzf /tmp/src.tgz --strip-components=1 -C ${INSTALL_DIR} \
 && rm /tmp/src.tgz

# `npm ci` for a clean, reproducible install straight from the committed
# package-lock.json. Dev deps are needed for `tsc`; `npm prune --omit=dev`
# strips them afterwards so only prod deps get copied on.
RUN npm ci \
 && npm run build \
 && npm prune --omit=dev

# =============================================================================
# Stage 2 — final: minimal runtime, non-root, correct signal handling.
# =============================================================================
FROM node:24-alpine AS final

ARG INSTALL_DIR
ARG NXX_CONF_PATH

# image.version tracks the nexxus-worker-transport-manager release fetched in the builder stage —
# keep it in sync with NEXXUS_WORKER_ARCHIVE_URL when bumping.
LABEL org.opencontainers.image.title="nexxus-worker-transport-manager" \
      org.opencontainers.image.description="Pluggable base image for the Nexxus Worker Transport Manager" \
      org.opencontainers.image.source="https://github.com/Mayhem93/nexxus-worker-transport-manager" \
      org.opencontainers.image.version="0.0.2" \
      org.opencontainers.image.licenses="MPL-2.0"

# Proper PID 1 via tini (reaps zombies + forwards signals), plus a dedicated,
# fixed-uid service account `nexxus` — like the redis/elasticsearch/postgres
# images, this runs under its own user:group rather than a generic account.
# (uid/gid 1001 avoids colliding with the base image's `node` user at 1000.)
RUN apk add --no-cache tini \
 && addgroup -g 1001 -S nexxus \
 && adduser  -u 1001 -S -D -H -h "${INSTALL_DIR}" -G nexxus nexxus

# NXX_CONF_PATH is both a build-time ARG (change the default location) and the
# runtime ENV the server reads to locate its config file.
ENV NXX_CONF_PATH=${NXX_CONF_PATH} \
    NODE_ENV=production

WORKDIR ${INSTALL_DIR}

# Compiled app + production node_modules + package.json, owned by the non-root
# `nexxus` user so a downstream `npm install <adapter>` can write here.
COPY --from=builder --chown=nexxus:nexxus ${INSTALL_DIR} ${INSTALL_DIR}

# Create the config directory (writable by nexxus) so a child image can COPY, or
# a runtime bind-mount can land, the config there. The base image ships NO config;
# starting it without one is a deliberate, fatal "config not found" at boot.
RUN mkdir -p "$(dirname "$NXX_CONF_PATH")" \
 && chown nexxus:nexxus "$(dirname "$NXX_CONF_PATH")"

USER nexxus

# Exec `node` directly (not `npm start`) so node is tini's direct child: it
# receives SIGTERM/SIGINT and its handler drains the event loop to completion.
# (An `npm start` wrapper exits first on stop, letting tini tear node down before
# it finishes — so the shutdown log never prints.) `npm` stays in the image for
# downstream adapter installs; it's just not in the runtime path.
#
# Tune the runtime via the NODE_OPTIONS env var (its allowlist includes
# --max-old-space-size, GC flags, etc.) rather than overriding this CMD: node
# merges NODE_OPTIONS on top of these flags, and --enable-source-maps stays baked
# here so it's always on even if a consumer sets NODE_OPTIONS.
ENTRYPOINT ["/sbin/tini", "-g", "--"]
CMD ["node", "--enable-source-maps", "dist/index.js"]
