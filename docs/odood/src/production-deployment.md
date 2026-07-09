# Production deployment

## Overview

Production installation focuses more on security and stability.
Thus, it does the following additional tasks:
- Creates separate user to run Odoo
- Creates systemd service or init script to run Odoo at startup
- Optionally configures:
  - logrotate
  - nginx
  - fail2ban
  - certbot

Also, production installation expects that it is running on a clean system, and no other Odoo is installed on the same system.

## Indirect dependencies

**Note** that *Odood* will not automatically install indirect dependencies, so you have to manually install the following system packages (if needed):
- [postgresql](https://www.postgresql.org/) - the PostgreSQL server must be installed manually before running `odood deploy` with the `--local-postgres` option.
- [wkhtmltopdf](https://github.com/wkhtmltopdf/packaging/releases) - required to generate PDF reports. See the [Odoo docs](https://github.com/odoo/odoo/wiki/Wkhtmltopdf) for more info.
- [nginx](https://nginx.org/) - if you want to expose the installed Odoo to the external world via `nginx`. In this case, Odood will automatically generate a template config for `nginx`.
- [certbot](https://certbot.eff.org/) - if you want to automatically generate [Let's Encrypt](https://letsencrypt.org/) certificates.
- [fail2ban](https://github.com/fail2ban/fail2ban) [Optional] - if you want to automatically block incorrect logins by IP. In this case Odood will automatically generate configs for `fail2ban`.

On *Ubuntu 24.04* the required dependencies can be installed via:

```bash
sudo apt install postgresql nginx certbot

wget -O /tmp/wkhtmltopdf-0.12.6.1-3.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install /tmp/wkhtmltopdf-0.12.6.1-3.deb
```

**Note**: choose the right release for your operating system when installing [wkhtmltopdf](https://github.com/wkhtmltopdf/packaging/releases).

## Deployment

Assuming all needed indirect system dependencies (in this example only the PostgreSQL server) are already installed,
use the following command to install Odoo 18 for production with local postgres:

```bash
sudo odood deploy -v 18 --local-postgres --supervisor=systemd
```

After this command completes, Odoo is installed and configured to use the local postgresql.
This Odoo instance will be managed by a `systemd` service.

**Note:** on a production installation each call to `odood` has to be run with `sudo` or as superuser.
Odood will automatically handle switching access rights when needed.

Also, it is recommended to use the [assembly](./assembly.md) functionality to manage third-party addons on production instances.
With an assembly the server can be deployed as follows:

```bash
sudo odood deploy -v 18 \
    --local-postgres \
    --supervisor=systemd \
    --assembly-repo=https://github.com/my/assembly
```

This way, the server will be automatically configured to use the assembly `https://github.com/my/assembly`.

## Key `odood deploy` flags

| Flag | Description |
|---|---|
| `-v <series>` / `--odoo-version` | Odoo series to deploy (default: `17.0`) |
| `--supervisor=<name>` | Process supervisor: `systemd`, `init-script`, or `odood` (default: `systemd`) |
| `--local-postgres` | Configure the local PostgreSQL server (requires PostgreSQL installed) |
| `--db-host` / `--db-port` / `--db-user` / `--db-password` | Connection to an external PostgreSQL (instead of `--local-postgres`) |
| `-w <n>` / `--workers` | Number of Odoo workers; `0` = threaded mode (default: `0`) |
| `--proxy-mode` | Enable `proxy_mode` in the Odoo config (behind a reverse proxy) |
| `--local-nginx` | Autoconfigure local nginx (requires nginx installed) |
| `--local-nginx-server-name=<name>` | Server name for the generated nginx config |
| `--local-nginx-ssl` | Enable SSL in the nginx config |
| `--local-nginx-ssl-cert` / `--local-nginx-ssl-key` | Paths to the SSL certificate/key (e.g. self-signed) |
| `--tls12-compat` | Also allow TLS 1.2 for older clients (default: TLS 1.3 only) |
| `--letsencrypt` | Enable [Let's Encrypt](https://letsencrypt.org/) configuration (requires certbot) |
| `--letsencrypt-email=<email>` | Email for the Let's Encrypt account |
| `--enable-logrotate` | Configure logrotate for Odoo logs |
| `--enable-fail2ban` | Configure fail2ban to block repeated failed logins (requires fail2ban installed) |
| `--assembly-repo=<url>` | Configure the instance to use an [assembly](./assembly.md) from this git repository |
| `--log-to-stderr` | No log file; log to stdout/stderr (for container builds) |
| `--use-system-ca-bundle` | Make Odoo use the system CA certificate store instead of the bundled certifi bundle |
| `--server-user-uid` / `--server-user-gid` | Create the Odoo system user/group with a fixed UID/GID (for container builds with a matching `securityContext`) |
| `--py-version` / `--node-version` | Build a specific Python / install a specific Node.js version |

Run `odood deploy --help` for the full list of options.

## Backup and restore

### Backing up databases

Odood stores backups in the `backups/` directory of the installation.

```bash
# Backup a single database
sudo odood db backup -d mydb

# Backup all databases on this instance
sudo odood db backup -a
```

It is good practice to back up before any upgrade or configuration change.

### Restoring from backup

```bash
sudo odood db restore mydb /path/to/odood/backups/mydb-2025-01-15.zip
```

If the target database already exists, drop it first:

```bash
sudo odood db drop mydb
sudo odood db restore mydb /path/to/odood/backups/mydb-2025-01-15.zip
```

## Upgrading

### Upgrading with assembly (recommended)

If the server is configured to use [Assembly](./assembly.md), a single command handles the full upgrade:

```bash
sudo odood assembly upgrade --backup
```

This will automatically:
1. Back up all databases
2. Pull the latest assembly changes
3. Relink addons
4. Update all addons in all databases
5. Restart the server

### Upgrading without assembly

If you manage third-party repositories directly:

```bash
# 1. Back up all databases
sudo odood db backup -a

# 2. Update Odoo itself to the latest revision of the current series
sudo odood venv update-odoo

# 3. Pull latest changes from all third-party repositories
sudo odood repo pull-all

# 4. Refresh the addon list and update addons in all databases
sudo odood addons update-list
sudo odood addons update --dir custom_addons
```

For more details on upgrade scenarios see [Upgrading Odoo](./upgrading.md).

## Complete sample: Public server

The following list of commands will install Odoo with configured nginx, postgresql, certbot and fail2ban on a publicly available server.

This sample assumes that you have control over your domain and have already pointed it at the server where Odoo is to be installed.

**Note**: update the wkhtmltopdf command below to match your architecture.

Run the following commands to get a complete production-ready Odoo installation on **Ubuntu 24.04**:

```bash
sudo apt-get update -yq    # update list of packages
sudo apt-get upgrade -yq   # upgrade packages

# Install required system dependencies
sudo apt-get install -yq wget nginx postgresql certbot fail2ban

# Download and install latest version of Odood
wget -O /tmp/odood.deb \
    "https://github.com/katyukha/Odood/releases/latest/download/odood_$(dpkg --print-architecture).deb"
sudo apt install -yq /tmp/odood.deb

# Download and install correct version of Wkhtmltopdf
wget -O /tmp/wkhtmltopdf-0.12.6.1-3.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install -yq /tmp/wkhtmltopdf-0.12.6.1-3.deb

# Deploy Odoo 18.0 on the server
sudo odood deploy \
    -v 18 \
    --local-postgres \
    --supervisor=systemd \
    --enable-logrotate \
    --enable-fail2ban \
    --local-nginx-server-name=my.test.server \
    --letsencrypt-email=me@my.test.server
```

## Complete sample: Private network server with self-signed SSL certificates

The following list of commands will install Odoo with configured nginx and postgresql on a server in a private network, with self-signed SSL certificates under the following paths:
- /etc/nginx/ssl/my.test.server.int.crt
- /etc/nginx/ssl/my.test.server.int.key

This sample assumes that you have already generated the self-signed certificates.

Run the following commands to get a complete production-ready Odoo installation on **Ubuntu 24.04**:

```bash
sudo apt-get update -yq    # update list of packages
sudo apt-get upgrade -yq   # upgrade packages

# Install required system dependencies
sudo apt-get install -yq wget nginx postgresql certbot fail2ban

# Download and install latest version of Odood
wget -O /tmp/odood.deb \
    "https://github.com/katyukha/Odood/releases/latest/download/odood_$(dpkg --print-architecture).deb"
sudo apt install -yq /tmp/odood.deb

# Download and install correct version of Wkhtmltopdf
wget -O /tmp/wkhtmltopdf-0.12.6.1-3.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install -yq /tmp/wkhtmltopdf-0.12.6.1-3.deb

# Deploy Odoo 18.0 on the server
sudo odood deploy \
    -v 18 \
    --local-postgres \
    --supervisor=systemd \
    --enable-logrotate \
    --local-nginx-server-name=my.test.server.int \
    --local-nginx-ssl \
    --local-nginx-ssl-cert=/etc/nginx/ssl/my.test.server.int.crt \
    --local-nginx-ssl-key=/etc/nginx/ssl/my.test.server.int.key
```
