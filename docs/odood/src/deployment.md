# Deployment Overview

Odood supports three main deployment patterns, each suited to a different operational context.
Choose the pattern that matches your team size, infrastructure, and operational preferences.
For all patterns, [Assembly](./assembly.md) is the recommended way to manage third-party addons in production environments.

## Patterns at a glance

| Pattern | Typical use | Key tool |
|---|---|---|
| Local development | Developer machine, multiple Odoo versions side by side | `odood init` |
| Docker Compose | Single-server, small team, easier ops than bare-metal | Prebuilt images + `ODOOD_OPT_*` |
| VPS / bare-metal | Traditional production, full control, systemd | `odood deploy` |

## How to choose

**Local development** is the fastest way to get Odoo running for day-to-day addon development.
It installs everything into a single directory, supports multiple isolated instances on one machine (different ports and database users), and requires no special privileges.

**Docker Compose** is a good fit when you want a simple, reproducible deployment on a single server without dealing with systemd, nginx configuration, or Python virtualenv setup.
The prebuilt Odood images have Odoo pre-installed and can be configured entirely through environment variables.
It is not ideal for horizontal scaling — multiple replicas require shared RWX storage for Odoo's data directory.

**VPS / bare-metal** gives you full control over the host system: dedicated service accounts, systemd unit files, nginx, logrotate, fail2ban, and Let's Encrypt integration.
This is the traditional approach for production installations where you manage the server directly.

## Next steps

- [Local Development](./deployment-local.md)
- [Docker Compose](./deployment-docker-compose.md)
- [Production (VPS)](./production-deployment.md)
- [Assembly](./assembly.md)
