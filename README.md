# nexxus-docker

> Pluggable base Docker images for the [Nexxus](https://github.com/Mayhem93/nexxus-lib) backend.

These are **base images** meant to be extended. A deployment builds `FROM` a base
image, supplies its own config, adds any custom adapters, and sets the env vars
its config needs.

| Image | Docker Hub | Status |
| ------- | ----------- | -------- |
| **API** | [`razvanbotea/nexxus-api`](https://hub.docker.com/r/razvanbotea/nexxus-api) | available |
| **Writer worker** | [`razvanbotea/nexxus-worker-writer`](https://hub.docker.com/r/razvanbotea/nexxus-worker-writer) | available |
| **Transport manager worker** | [`razvanbotea/nexxus-worker-transport-manager`](https://hub.docker.com/r/razvanbotea/nexxus-worker-transport-manager) | available |
| WebSockets transport worker | — | planned |

Each image's tags track its own source component's releases — e.g. the API image
tracks [`nexxus-api`](https://github.com/Mayhem93/nexxus-api) and the writer worker
tracks [`nexxus-worker-writer`](https://github.com/Mayhem93/nexxus-worker-writer).

---

## What the API image contains

- Node 24 (Alpine), the compiled `nexxus-api` server + its production dependencies.
- The built-in adapters (`WinstonNexxusLogger`, `NexxusElasticsearchDb`, `NexxusRabbitMq`).
- Runs as a non-root user (`nexxus`, uid/gid 1001) under `tini` as PID 1.

It ships **no config** — starting it without one is a deliberate, fatal error.
You provide the config; the server reads it from `$NXX_CONF_PATH`.

**Backing services required at runtime:** Elasticsearch, RabbitMQ, and Redis
must be reachable at the hosts named in your config.

---

## Quick start

### Option A — bind-mount a config

```bash
docker run --rm -p 5000:5000 \
  -v "$PWD/api.conf.json:/etc/nexxus/api.conf.json:ro" \
  razvanbotea/nexxus-api:0.0.4
```

### Option B — build a deployment image

Bake your config (and any custom adapters) into your own image on top of the base.
See [`example.Dockerfile`](example.Dockerfile) for a complete, commented template:

```dockerfile
FROM razvanbotea/nexxus-api:0.0.4

# 1. Provide the config at the path the server reads
COPY --chown=nexxus:nexxus api.conf.json /etc/nexxus/api.conf.json

# 2. (optional) add custom adapters, then reference them in the config
# RUN npm install @myorg/nexxus-postgres-adapter

# 3. (optional) tune the runtime
# ENV NODE_OPTIONS=--max-old-space-size=768
```

```bash
docker build -t my-nexxus-api .
docker run --rm -p 5000:5000 my-nexxus-api
```

A starter config is in [`example.conf.json`](example.conf.json); the full config
reference lives in the [`nexxus-api` README](https://github.com/Mayhem93/nexxus-api#configuration).

---

## Writer worker

The writer worker consumes queued model writes, persists them to the database, and
notifies the transport manager. It's a **background queue consumer — no HTTP port**,
so there's nothing to publish with `-p`. Otherwise it follows the same base-image
conventions as the API: no config baked in, non-root `nexxus` user, `tini` as PID 1,
and `NODE_OPTIONS` runtime tuning.

| Property | Value |
| ---------- | ------- |
| Docker Hub | [`razvanbotea/nexxus-worker-writer`](https://hub.docker.com/r/razvanbotea/nexxus-worker-writer) |
| Source | [`nexxus-worker-writer`](https://github.com/Mayhem93/nexxus-worker-writer) |
| Install dir | `/usr/local/nexxus-worker-writer` |
| `NXX_CONF_PATH` default | `/etc/nexxus/worker-writer.conf.json` |

```bash
# Run with a bind-mounted config (no port to publish)
docker run --rm \
  -v "$PWD/worker-writer.conf.json:/etc/nexxus/worker-writer.conf.json:ro" \
  razvanbotea/nexxus-worker-writer:0.0.1
```

Building a deployment image on top, the [Configuration](#configuration) below, and
custom adapters all work exactly as for the API — just without the port.

---

## Transport manager worker

The transport manager worker consumes the transport-manager queue, resolves which
devices are subscribed (via Redis), and routes each notification to the right
transport-specific queue. Like the writer, it's a **background queue consumer — no
HTTP port** — and follows the same base-image conventions (no config baked in,
non-root `nexxus` user, `tini` as PID 1, `NODE_OPTIONS` runtime tuning).

| Property | Value |
| ---------- | ------- |
| Docker Hub | [`razvanbotea/nexxus-worker-transport-manager`](https://hub.docker.com/r/razvanbotea/nexxus-worker-transport-manager) |
| Source | [`nexxus-worker-transport-manager`](https://github.com/Mayhem93/nexxus-worker-transport-manager) |
| Install dir | `/usr/local/nexxus-worker-transport-manager` |
| `NXX_CONF_PATH` default | `/etc/nexxus/worker-transport-manager.conf.json` |

```bash
# Run with a bind-mounted config (no port to publish)
docker run --rm \
  -v "$PWD/worker-transport-manager.conf.json:/etc/nexxus/worker-transport-manager.conf.json:ro" \
  razvanbotea/nexxus-worker-transport-manager:0.0.1
```

Building a deployment image on top, the [Configuration](#configuration) below, and
custom adapters all work exactly as for the API — just without the port.

---

## Configuration

### Environment variables

| Variable | Default | Purpose |
| ---------- | --------- | --------- |
| `NXX_CONF_PATH` | per image | Where the process reads its config file (API `/etc/nexxus/api.conf.json`, writer worker `/etc/nexxus/worker-writer.conf.json`). |
| `NXX_LOG_LEVEL` | (from config) | Overrides `logger.level`. Other per-service overrides are derived from each service's schema. |
| `NODE_OPTIONS` | (unset) | Node runtime flags, e.g. `--max-old-space-size=768`. Size the heap to ~75% of the container's memory limit to avoid OOM kills. `--enable-source-maps` is always on. |

### Custom adapters

Logger / database / message-queue adapters are chosen in the config's `app`
section. Built-ins resolve by class name; custom adapters are npm packages
`npm install`ed into the image and referenced by package name:

```json
{ "app": { "logger": "@myorg/nexxus-datadog-logger" } }
```

### A note on the port

Applies to images that listen (the API today; the WebSockets transport worker later)
— the writer and transport-manager workers have no port. `EXPOSE` is metadata only:
the actual listen port comes from `app.port` in the config (default `5000`). Publish
the port that matches your config: `-p <host>:<app.port>`.

---

## Building the base image yourself

```bash
docker build -t nexxus-api ./api
```

Build args (`--build-arg`):

| Arg | Default | Purpose |
| ----- | --------- | --------- |
| `INSTALL_DIR` | `/usr/local/nexxus-api` | Where the app is installed (also the WORKDIR). |
| `NXX_CONF_PATH` | `/etc/nexxus/api.conf.json` | Default config path baked as `ENV`. |
| `APP_PORT` | `5000` | Port used for `EXPOSE`. |
| `NEXXUS_API_ARCHIVE_URL` | public GitHub tarball | Override only to build from a private/closed-source mirror. |

The Node version and the `nexxus-api` release are intentionally fixed in the
Dockerfile (not build args) — they move on a release basis.

The **workers** build the same way from their own directories (`./worker-writer`,
`./worker-transport-manager`) — same args minus `APP_PORT`, with the source-override
arg `NEXXUS_WORKER_ARCHIVE_URL`.

---

## License

[MPL-2.0](LICENSE)
