# syntax=docker/dockerfile:1
#
# EXAMPLE deployment image — how to consume the nexxus-api base image.
# -----------------------------------------------------------------------------
# The base image (razvanbotea/nexxus-api) ships the compiled API server
# with the BUILT-IN adapters but no config. A real deployment extends it to:
#   1. provide a config file at $NXX_CONF_PATH,
#   2. (optionally) install custom adapter packages named in that config,
#   3. set any ENV vars the config/services expect.
#
# Build:
#   docker build -f example.Dockerfile -t my-nexxus-deployment .
#
# Run (map the app port; app.port in the config is 5000). Requires the backing
# services (elasticsearch / rabbitmq / redis) to be reachable at the hostnames
# in example.conf.json — e.g. on a shared docker-compose or k8s network:
#   docker run --rm -p 5000:5000 my-nexxus-deployment
# -----------------------------------------------------------------------------

FROM razvanbotea/nexxus-api:0.0.3

# The base image already sets, so you don't repeat them:
#   WORKDIR  /usr/local/nexxus-api   (install dir; where node_modules lives)
#   USER     nexxus                  (non-root, uid/gid 1001)
#   ENV      NXX_CONF_PATH=/etc/nexxus/api.conf.json
#   ENTRYPOINT ["/sbin/tini","-g","--"]
#   CMD ["node","--enable-source-maps","dist/index.js"]   +   EXPOSE 5000
# and it created the config directory writable by the `nexxus` user.

# --- 1. Provide the config ----------------------------------------------------
# Bake the deployment config into the image at the path the server reads.
# (Alternative: omit this and bind-mount at runtime instead:
#    docker run -v "$PWD/example.conf.json":/etc/nexxus/api.conf.json ... )
# The local config file to bake in (relative to the build context). Override to
# ship a different config without editing this file:
#   docker build -f example.Dockerfile --build-arg CONF_SRC=prod.conf.json .
ARG CONF_SRC=example.conf.json
COPY --chown=nexxus:nexxus ${CONF_SRC} ${NXX_CONF_PATH}

# --- 2. (Optional) add pluggable adapters -------------------------------------
# Custom logger/DB/MQ adapters are npm packages dynamic-imported from the app's
# node_modules. Install them here, then reference them by package name in the
# config's "app" section (e.g. "logger": "@myorg/nexxus-datadog-logger").
# The install dir is owned by `nexxus`, so this needs no switch to root:
#
# RUN npm install @myorg/nexxus-datadog-logger @myorg/nexxus-postgres-adapter
#
# If an adapter pulls native modules that need build tools or system libs,
# switch to root for that step only, then drop back:
#
# USER root
# RUN apk add --no-cache <lib>
# USER nexxus

# --- 3. Runtime configuration via ENV -----------------------------------------
# Registered services expose schema-derived env overrides; NXX_LOG_LEVEL is a
# confirmed one (overrides logger.level). Prefer env vars — supplied at
# `docker run -e ...` / in your orchestrator — for secrets and per-environment
# values rather than baking them into the config file above.
ENV NXX_LOG_LEVEL=debug

# Tune the node runtime via NODE_OPTIONS instead of overriding the base CMD (the
# base keeps --enable-source-maps in its CMD; node merges NODE_OPTIONS on top).
# Size the V8 heap to ~75% of the container's memory limit to avoid OOM kills —
# bake a default here, or set it per-deploy via `docker run -e NODE_OPTIONS=...`:
    
# ENV NODE_OPTIONS=--max-old-space-size=768      # e.g. for a ~1Gi memory limit

# That's it — ENTRYPOINT/CMD/EXPOSE are inherited from the base image.
# Only add an `EXPOSE <port>` here if you change app.port in the config.
