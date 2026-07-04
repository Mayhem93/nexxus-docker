# nexxus-docker

> Pluggable base Docker images for the [Nexxus](https://github.com/Mayhem93/nexxus-lib) backend.

These are **base images** meant to be extended. A deployment builds `FROM` a base
image, supplies its own config, adds any custom adapters, and sets the env vars
its config needs.

| Image | Docker Hub | Status |
|-------|-----------|--------|
| **API** | [`razvanbotea/nexxus-api`](https://hub.docker.com/r/razvanbotea/nexxus-api) | available |
| Writer worker | — | planned |
| Transport manager worker | — | planned |
| WebSockets transport worker | — | planned |

Image tags track [`nexxus-api`](https://github.com/Mayhem93/nexxus-api) releases
(see [Docker Hub tags](https://hub.docker.com/r/razvanbotea/nexxus-api/tags)).

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

## Configuration

### Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `NXX_CONF_PATH` | `/etc/nexxus/api.conf.json` | Where the server reads its config file. |
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

`EXPOSE` is metadata only — the actual listen port comes from `app.port` in the
config (default `5000`). Publish the port that matches your config: `-p <host>:<app.port>`.

---

## Building the base image yourself

```bash
docker build -t nexxus-api ./api
```

Build args (`--build-arg`):

| Arg | Default | Purpose |
|-----|---------|---------|
| `INSTALL_DIR` | `/usr/local/nexxus-api` | Where the app is installed (also the WORKDIR). |
| `NXX_CONF_PATH` | `/etc/nexxus/api.conf.json` | Default config path baked as `ENV`. |
| `APP_PORT` | `5000` | Port used for `EXPOSE`. |
| `NEXXUS_API_ARCHIVE_URL` | public GitHub tarball | Override only to build from a private/closed-source mirror. |

The Node version and the `nexxus-api` release are intentionally fixed in the
Dockerfile (not build args) — they move on a release basis.

---

## License

[MPL-2.0](LICENSE)
