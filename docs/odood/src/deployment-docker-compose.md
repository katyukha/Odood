# Docker Compose Deployment

This page covers deploying Odoo with the prebuilt Odood Docker images using Docker Compose.

> **Use with care.**
> The Docker Compose pattern is well suited for **test environments, CI pipelines, and teams with solid Docker experience**.
> Docker Compose based installations are not battle-tested in production yet.
> If you need a stable, low-maintenance production setup, prefer [Production (VPS)](./production-deployment.md) instead.

## When to use

Docker Compose is a reasonable choice when:

- You need a **test or staging environment** that mirrors production without the overhead of bare-metal setup.
- You are running **CI pipelines** and want a clean, reproducible Odoo stack per run.
- Your team has **solid Docker and Docker Compose experience** and is comfortable debugging container-level issues.
- You want configuration managed entirely through **environment variables**.

It is **not** recommended for production unless your team already operates Docker Compose deployments confidently and understands the operational trade-offs.
It is also **not** the right choice for horizontal scaling — multiple Odoo replicas need shared RWX storage for `/opt/odoo/data`.

For traditional bare-metal or VPS production deployments see [Production (VPS)](./production-deployment.md).

## Prerequisites

- [Docker Engine](https://docs.docker.com/engine/install/) (v20.10+)
- [Docker Compose v2](https://docs.docker.com/compose/install/) (the `docker compose` plugin, not the legacy `docker-compose` binary)

## Prebuilt images

The official Odood Docker images are published to the GitHub Container Registry:

```
ghcr.io/katyukha/odood/odoo/{serie}:latest
```

Available series: `16.0`, `17.0`, `18.0`, `19.0`.

> **Note:** The `--config-from-env` flag and `ODOOD_OPT_*` environment variable support are compiled into these images using the `-d-version OdoodInDocker` build flag.
> They are **not** available in the Debian package or source builds.
> See the `ODOOD_OPT_*` reference table in [Development Workflow](./development-workflow.md) for a full list of supported variables.

## HTTP example

The following Compose file runs Odoo 18 with PostgreSQL behind a [Traefik](https://traefik.io/) reverse proxy over plain HTTP.
It corresponds to the example in [`examples/docker-compose/odoo-and-db/`](https://github.com/katyukha/Odood/tree/main/examples/docker-compose/odoo-and-db).

```yaml
# Odood Docker Compose Example — HTTP
#
# Runs Odoo 18 with PostgreSQL behind a Traefik reverse proxy over plain HTTP.
#
# Usage:
#   docker compose up -d
#
# Odoo will be available at http://localhost
# Traefik dashboard at http://localhost:8080 (disable in production)

volumes:
    odood-example-db-data:
    odood-example-odoo-data:

services:
    odood-example-db:
        image: postgres:16
        container_name: odood-example-db
        environment:
            # Credentials must match ODOOD_OPT_DB_USER / ODOOD_OPT_DB_PASSWORD below.
            POSTGRES_USER: odoo
            POSTGRES_PASSWORD: odoo-db-pass
            # Prevents PostgreSQL from auto-creating a default database;
            # all Odoo databases must be created by Odoo itself.
            POSTGRES_DB: postgres
        volumes:
            - odood-example-db-data:/var/lib/postgresql/data
        healthcheck:
            test: ["CMD-SHELL", "pg_isready -U odoo"]
            interval: 10s
            timeout: 5s
            retries: 5
            start_period: 10s
        restart: unless-stopped

    odood-example-odoo:
        image: ghcr.io/katyukha/odood/odoo/18.0:latest
        container_name: odood-example-odoo
        labels:
            # Route all HTTP traffic to Odoo on port 8069.
            - "traefik.enable=true"
            - "traefik.http.routers.odoo-route.rule=Host(`localhost`)"
            - "traefik.http.routers.odoo-route.service=odoo-service"
            - "traefik.http.routers.odoo-route.entrypoints=web"
            - "traefik.http.services.odoo-service.loadbalancer.server.port=8069"
            # Route /websocket traffic to the Gevent worker on port 8072.
            - "traefik.http.routers.odoo-ge-route.rule=Host(`localhost`) && Path(`/websocket`)"
            - "traefik.http.routers.odoo-ge-route.service=odoo-ge-service"
            - "traefik.http.routers.odoo-ge-route.entrypoints=web"
            - "traefik.http.services.odoo-ge-service.loadbalancer.server.port=8072"
        depends_on:
            odood-example-db:
                # Wait until PostgreSQL is healthy before starting Odoo.
                condition: service_healthy
        environment:
            # Database connection — must match POSTGRES_USER/PASSWORD above.
            ODOOD_OPT_DB_HOST: odood-example-db
            ODOOD_OPT_DB_USER: odoo
            ODOOD_OPT_DB_PASSWORD: odoo-db-pass
            # Odoo master password used to create/drop databases via the web UI.
            ODOOD_OPT_ADMIN_PASSWD: admin
            # Number of Odoo worker processes. Increase for higher load.
            # Rule of thumb: (CPU cores * 2) + 1, minimum 2.
            ODOOD_OPT_WORKERS: "2"
            # Required when Odoo runs behind a reverse proxy.
            ODOOD_OPT_PROXY_MODE: "True"
        volumes:
            - odood-example-odoo-data:/opt/odoo/data
        restart: unless-stopped

    odood-example-traefik:
        image: "traefik:v3.2"
        container_name: "odood-example-traefik"
        command:
            - "--api.insecure=true"
            - "--providers.docker=true"
            - "--providers.docker.exposedbydefault=false"
            - "--entryPoints.web.address=:80"
        ports:
            - "80:80"
            # Traefik dashboard — remove in production.
            - "8080:8080"
        volumes:
            - "/var/run/docker.sock:/var/run/docker.sock:ro"
        restart: unless-stopped
```

## HTTPS example

The HTTPS example adds TLS termination at the Traefik layer with automatic HTTP→HTTPS redirect.
It corresponds to [`examples/docker-compose/odoo-and-db-ssl/`](https://github.com/katyukha/Odood/tree/main/examples/docker-compose/odoo-and-db-ssl).

Before starting, place your certificate and key under `./traefik/certs/` and configure `./traefik/traefik-certs.yml` to reference them.

```yaml
# Odood Docker Compose Example — HTTPS
#
# Runs Odoo 18 with PostgreSQL behind Traefik with TLS termination.
# HTTP (port 80) is automatically redirected to HTTPS (port 443).

volumes:
    odood-example-ssl-db-data:
    odood-example-ssl-odoo-data:

services:
    odood-example-ssl-db:
        image: postgres:16
        container_name: odood-example-ssl-db
        environment:
            POSTGRES_USER: odoo
            POSTGRES_PASSWORD: odoo-db-pass
            POSTGRES_DB: postgres
        volumes:
            - odood-example-ssl-db-data:/var/lib/postgresql/data
        healthcheck:
            test: ["CMD-SHELL", "pg_isready -U odoo"]
            interval: 10s
            timeout: 5s
            retries: 5
            start_period: 10s
        restart: unless-stopped

    odood-example-ssl-odoo:
        image: ghcr.io/katyukha/odood/odoo/18.0:latest
        container_name: odood-example-ssl-odoo
        labels:
            - "traefik.enable=true"
            - "traefik.http.routers.odoo-route.rule=Host(`localhost`)"
            - "traefik.http.routers.odoo-route.service=odoo-service"
            - "traefik.http.routers.odoo-route.entrypoints=webssl"
            - "traefik.http.routers.odoo-route.tls=true"
            - "traefik.http.services.odoo-service.loadbalancer.server.port=8069"
            - "traefik.http.routers.odoo-ge-route.rule=Host(`localhost`) && Path(`/websocket`)"
            - "traefik.http.routers.odoo-ge-route.service=odoo-ge-service"
            - "traefik.http.routers.odoo-ge-route.entrypoints=webssl"
            - "traefik.http.routers.odoo-ge-route.tls=true"
            - "traefik.http.services.odoo-ge-service.loadbalancer.server.port=8072"
        depends_on:
            odood-example-ssl-db:
                condition: service_healthy
        environment:
            ODOOD_OPT_DB_HOST: odood-example-ssl-db
            ODOOD_OPT_DB_USER: odoo
            ODOOD_OPT_DB_PASSWORD: odoo-db-pass
            ODOOD_OPT_ADMIN_PASSWD: admin
            ODOOD_OPT_WORKERS: "2"
            ODOOD_OPT_PROXY_MODE: "True"
        volumes:
            - odood-example-ssl-odoo-data:/opt/odoo/data
        restart: unless-stopped

    odood-example-ssl-traefik:
        image: "traefik:v3.2"
        container_name: "odood-example-ssl-traefik"
        command:
            - "--providers.docker=true"
            - "--providers.docker.exposedbydefault=false"
            - "--providers.file.filename=/traefik-certs.yml"
            - "--entryPoints.web.address=:80"
            - "--entryPoints.webssl.address=:443"
            - "--entrypoints.web.http.redirections.entrypoint.to=webssl"
            - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
        ports:
            - "80:80"
            - "443:443"
        volumes:
            - "./traefik/traefik-certs.yml:/traefik-certs.yml"
            - "./traefik/certs/:/certs/"
            - "/var/run/docker.sock:/var/run/docker.sock:ro"
        restart: unless-stopped
```

## Database initialisation

On first start, Odoo's web UI presents a database creation form accessible at `http://localhost` (or `https://localhost` for the SSL example).

Alternatively, initialise a database from the command line:

```bash
docker compose exec odood-example-odoo \
    odood --config-from-env db create --demo my-db
```

To create a database and mark it as initialized (skipping the web setup wizard):

```bash
docker compose exec odood-example-odoo \
    odood --config-from-env db ensure-initialized --demo my-db
```

## Backup and restore

Back up all databases to `/opt/odoo/data/backups/` inside the container:

```bash
docker compose exec odood-example-odoo \
    odood --config-from-env db backup -a
```

The backup files are stored in the `odood-example-odoo-data` volume. Copy them out with `docker cp` or mount a host path to `/opt/odoo/data/backups/`.

Restore a specific database from a backup file:

```bash
docker compose exec odood-example-odoo \
    odood --config-from-env db restore my-db /opt/odoo/data/backups/my-db-backup.zip
```

## Upgrading

Pull the latest images and recreate the containers:

```bash
docker compose pull
docker compose up -d
```

Odoo will restart with the new image.

> **Note:** For assembly-based deployments, use the dedicated workflow in
> [Upgrading assembly-based deployments](#upgrading-assembly-based-deployments) below —
> it stops Odoo first, runs the addon update step, and covers recovery.

## Using assembly images

When third-party addons are managed with [Assembly](./assembly.md), the assembly's addon directory
(`dist/`) is baked into a custom Docker image at build time — not cloned or mounted at runtime.
Every assembly release becomes a distinct, pinned image that can be rolled back if needed.

### Building assembly images

Odood generates the `Dockerfile` automatically. Add `--dockerfile` to the `assembly sync` command
in your CI workflow and it will be created (or updated) on every sync:

```bash
odood --config-from-env assembly sync \
    --changelog \
    --dockerfile \
    --commit --push
```

The generated Dockerfile:
- Copies `odood-assembly.yml` and `dist/` into `/opt/odoo/assembly/`
- Runs `odood assembly use /opt/odoo/assembly` to register the assembly in `odood.yml`
- Runs `odood assembly link` to create symlinks in `custom_addons/`, install Python requirements, and make addons visible to Odoo

Registering the assembly is what makes `--assembly` work in upgrade commands inside the container.
The image inherits the base image's `CMD`, which already includes `--wait-pg`, so no entrypoint customisation is needed.

See [Assembly CI — Full release cycle](./assembly.md#full-release-cycle) for complete GitHub
Actions workflows covering sync, PR creation, and image publishing.

### Image tags and docker-compose.yml

The recommended CI workflow publishes two tags per release derived from the assembly `VERSION` file
(e.g. `18.0.1.2.3`):

- **Full version** (`18.0.1.2.3`) — pinned; use this in `docker-compose.yml`.
- **Minor version** (`18.0.1.2`) — floating; always points to the latest patch of that minor.

Always pin to the full version tag in `docker-compose.yml` — never `:latest`.
An explicit tag lets you roll back to the previous image if an upgrade fails.
Pass the image reference as an environment variable so it can be updated at upgrade time
without editing the Compose file directly:

```yaml
services:
  odoo:
    image: ${ODOO_IMAGE}   # e.g. ghcr.io/my-org/my-assembly:18.0.1.2.3
    depends_on:
      db:
        condition: service_healthy
    environment:
      ODOOD_OPT_DB_HOST: db
      ODOOD_OPT_DB_USER: odoo
      ODOOD_OPT_DB_PASSWORD: odoo-db-pass
      ODOOD_OPT_ADMIN_PASSWD: admin
      ODOOD_OPT_WORKERS: "2"
      ODOOD_OPT_PROXY_MODE: "True"
    volumes:
      - odoo-data:/opt/odoo/data
    restart: unless-stopped
```

## Upgrading assembly-based deployments

Running two different versions of addon code against the same database simultaneously risks
corruption. **Always stop Odoo before running addon updates**, even in containerised environments.

Add the following `odoo-upgrade` service to your `docker-compose.yml`. It shares the image and
data volume with the main `odoo` service but only runs on demand via the `upgrade` profile:

```yaml
  odoo-upgrade:
    image: ${ODOO_IMAGE}
    profiles: [upgrade]
    depends_on:
      db:
        condition: service_healthy
    environment:
      ODOOD_OPT_DB_HOST: db        # match your DB service name
      ODOOD_OPT_DB_USER: odoo
      ODOOD_OPT_DB_PASSWORD: odoo-db-pass
    command: >
      bash -c "
        odood --config-from-env db backup -a &&
        odood --config-from-env addons install --missing-only --assembly &&
        odood --config-from-env addons update --installed-only --assembly
      "
    volumes:
      - odoo-data:/opt/odoo/data
    restart: "no"
```

What each command in the upgrade sequence does:

- `db backup -a` — backs up every database before any changes are made.
- `addons install --missing-only --assembly` — installs assembly addons not yet present in any
  database (handles newly added modules across releases). Applies to all databases by default.
- `addons update --installed-only --assembly` — updates only addons that are already installed,
  skipping uninstalled ones (safe and idempotent). Applies to all databases by default.

`--assembly` works because the generated Dockerfile registers the assembly in `odood.yml`
via `odood assembly use`, so the container knows where to find the assembly addons.

### Upgrade workflow

```bash
# Set the new assembly image version (explicit tag — never :latest)
export ODOO_IMAGE=ghcr.io/my-org/my-assembly:18.0.1.2.3

# 1. Pull the new image
docker compose pull

# 2. Stop Odoo — the DB container keeps running so the upgrade container can connect
docker compose stop odoo

# 3. Backup all databases, install new assembly addons, update changed addons
docker compose --profile upgrade run --rm odoo-upgrade

# 4a. Exit 0 — start Odoo with the new image
docker compose up -d odoo

# 4b. Non-zero — see Recovery below; Odoo remains stopped until you intervene
```

### Recovery

If the upgrade fails, restore every database from its pre-upgrade backup and restart Odoo with
the previous image.

```bash
# 1. List the backups created before the failed upgrade
docker compose run --rm --no-deps odoo-upgrade \
    ls /opt/odoo/data/backups/

# 2. Restore each database from its pre-upgrade backup
#    Repeat for every database, replacing the name and timestamp
docker compose run --rm --no-deps odoo-upgrade \
    odood --config-from-env db restore mydb \
        /opt/odoo/data/backups/mydb-TIMESTAMP.zip

# 3. Roll back to the previous image and start Odoo
export ODOO_IMAGE=ghcr.io/my-org/my-assembly:18.0.1.2.2
docker compose up -d odoo
```

> **Important:** If `addons update` partially succeeded before the failure (some modules updated,
> then a crash), the database is in a mixed state — some modules at the new version, others at
> the old. **Do not attempt to undo partial updates manually.** Restore from the pre-upgrade
> backup; that is the only clean recovery path.

> **`--no-deps`** starts the upgrade container without attempting to start its declared
> dependencies — safe to use in recovery when the DB container is already running.

## Scaling caveat

Running multiple Odoo replicas requires that `/opt/odoo/data` is stored on shared, RWX-capable storage (e.g. NFS or a cloud file share) so that all replicas can read and write session files and filestore. Without this, session state will be inconsistent across replicas.
