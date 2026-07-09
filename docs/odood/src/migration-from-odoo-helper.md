# Migrating from odoo-helper-scripts

This page guides existing [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/) users through migrating to Odood.

## What stays the same

The project directory layout is **identical** — `backups/`, `conf/`, `custom_addons/`,
`data/`, `downloads/`, `odoo/`, `repositories/`, `venv/` are all in the same places.
Your existing Odoo installation, databases, and cloned repositories do not need to move.

The only structural change is the project config file:
`odoo-helper.conf` (Bash variable exports) is replaced by `odood.yml` (YAML).

## Migrating an existing project

Odood can read an existing `odoo-helper.conf` and generate `odood.yml` automatically:

```bash
# In the root of your existing odoo-helper project
odood discover odoo-helper

# For a system-wide (production) installation managed as root
sudo odood discover odoo-helper --system
```

This reads `odoo-helper.conf`, creates `odood.yml` in the same directory, and sets up the
virtualenv wrapper that Odood needs. Your existing Odoo installation and data are untouched.

## Command reference

Most commands map directly. The main differences are:
- Repository management moved under `odood repo`
- Virtualenv utilities moved under `odood venv`
- CI / dev tooling moved under `odood repo`

### Repository management

| odoo-helper-scripts | odood |
|:---|:---|
| `odoo-helper fetch --repo URL` | `odood repo add URL` |
| `odoo-helper fetch --github user/repo` | `odood repo add --github user/repo` |
| `odoo-helper fetch --oca repo` | `odood repo add --oca repo` |
| `odoo-helper link .` | `odood addons link .` |
| `odoo-helper addons update-list` | `odood addons update-list` |

### Server management

| odoo-helper-scripts | odood |
|:---|:---|
| `odoo-helper server start` | `odood server start` |
| `odoo-helper server stop` | `odood server stop` |
| `odoo-helper server restart` | `odood server restart` |
| `odoo-helper server log` | `odood server log` |
| `odoo-helper server ps` | `odood server status` |

### Addon management

| odoo-helper-scripts | odood |
|:---|:---|
| `odoo-helper addons install` | `odood addons install` |
| `odoo-helper addons update` | `odood addons update` |
| `odoo-helper addons uninstall` | `odood addons uninstall` |

### Database management

| odoo-helper-scripts | odood |
|:---|:---|
| `odoo-helper db list` / `lsd` | `odood db list` |
| `odoo-helper db create` | `odood db create` |
| `odoo-helper db drop` | `odood db drop` |
| `odoo-helper db backup` | `odood db backup` |
| `odoo-helper db restore` | `odood db restore` |
| `odoo-helper db copy` | `odood db copy` |
| `odoo-helper db rename` | `odood db rename` |

### Testing

| odoo-helper-scripts | odood |
|:---|:---|
| `odoo-helper test -m addon` | `odood test -t addon` |

Note: `odood test` takes module names as positional arguments (no `-m` flag);
`-t` runs the tests on a temporary database.

### Translations

| odoo-helper-scripts | odood |
|:---|:---|
| `odoo-helper tr regenerate` | `odood tr regenerate` |

### Virtualenv / Python utilities

| odoo-helper-scripts | odood |
|:---|:---|
| `odoo-helper update-odoo` | `odood venv update-odoo` |
| `odoo-helper exec CMD` | `odood venv run -- CMD` |
| `odoo-helper pip` | `odood venv pip` |
| `odoo-helper python` | `odood venv python` |
| `odoo-helper ipython` | `odood venv ipython` |

### CI / dev tooling

| odoo-helper-scripts | odood |
|:---|:---|
| `odoo-helper ci check-versions-git` | `odood repo check-versions` |
| `odoo-helper ci fix-versions` | `odood repo bump-versions` |
| `odoo-helper ci do-forward-port` | `odood repo do-forward-port` |
| `odoo-helper ci auto-migrate-modules` | `odood repo migrate-addons` |
| `odoo-helper repo fix-version-conflict` | `odood repo fix-version-conflict` |
| `odoo-helper lint pylint` / `flake8` / `style` | `odood pre-commit run` |

When setting up pre-commit on a repository migrated from odoo-helper-scripts, use the
`--odoo-helper-compat` flag to generate a check-only configuration that matches
odoo-helper's linting behaviour (no auto-formatting):

```bash
odood pre-commit init --odoo-helper-compat
```

### Project info

| odoo-helper-scripts | odood |
|:---|:---|
| `odoo-helper status` | `odood status` |
| `odoo-helper print-config` | `odood info` |

## What is not available in Odood

The following odoo-helper-scripts features do not have equivalents in Odood yet:

- **`odoo-helper scaffold`** — no addon/repo scaffolding command yet

## What is new in Odood

- **[Assembly](./assembly.md)** — the recommended way to manage third-party addons on
  production servers. Assembly replaces the pattern of cloning multiple repositories
  directly on each server.
- **[`odood deploy`](./production-deployment.md)** — one-command production deployment with
  systemd, nginx, logrotate, fail2ban, and Let's Encrypt integration.
