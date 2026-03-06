# Local Development

This page covers everything you need to run one or more Odoo instances on a developer machine using `odood init`.

## Prerequisites

The following system packages are required:

- **PostgreSQL** — local database server. Install via your package manager (e.g. `sudo apt install postgresql`).
- **Python build dependencies** — Odood creates a Python virtualenv for Odoo. Usually the standard `python3`, `python3-dev`, and `python3-venv` packages suffice.
- **wkhtmltopdf** (optional) — required only if you need to generate PDF reports. Download from the [wkhtmltopdf releases](https://github.com/wkhtmltopdf/packaging/releases) page and install the `.deb` that matches your OS.

## Basic installation

Minimal installation of Odoo 18:

```bash
odood init -i odoo-18 -v 18
```

Typical installation with a dedicated database user and HTTP port (recommended when running multiple instances):

```bash
odood init -i odoo-18 -v 18 --db-user=odoo18 --http-port=18069
```

After the command completes, Odoo is installed in the `odoo-18` directory. Any subsequent `odood` command run from inside that directory (or any subdirectory) automatically targets that instance.

## Key `odood init` flags

### Version and install type

| Flag | Description |
|---|---|
| `-v <series>` | Odoo series to install (`16`, `17`, `18`, `19`, …) |
| `--install-type=archive` | Install from the official Odoo source archive (default) |
| `--install-type=git` | Clone from the Odoo git repository (enables `odood venv update-odoo`) |

### Database

| Flag | Description |
|---|---|
| `--db-user=<user>` | PostgreSQL role for this instance (default: `odoo`). The role must already exist unless `--create-db-user` is also passed. |
| `--db-password=<pass>` | Password for the PostgreSQL role (default: `odoo`) |
| `--db-host=<host>` | PostgreSQL host (default: `localhost`) |
| `--db-port=<port>` | PostgreSQL port (default: `5432`) |
| `--create-db-user` | Create the PostgreSQL role automatically. Requires `sudo`. **Not recommended on macOS** — PostgreSQL installation methods on macOS vary and the automatic user creation may not work reliably. |

### HTTP

| Flag | Description |
|---|---|
| `--http-port=<port>` | Port Odoo listens on (default: `8069`) |
| `--longpolling-port=<port>` | Gevent / long-polling port (default: `8072`) |

### Python and Node

| Flag | Description |
|---|---|
| `--python=<path>` | Path to the Python executable to use for the virtualenv |
| `--node-version=<ver>` | Node.js version to install (for frontend assets) |
| `--pyenv` | Use pyenv to manage the Python version (see macOS section) |

### Advanced

| Flag | Description |
|---|---|
| `--repo=<url>` | Git URL of a third-party addon repository to add during init |
| `--branch=<ref>` | Branch/ref for the `--repo` repository |

Run `odood init --help` to see the full list of options.

## Multiple instances on one machine

Each instance needs a unique combination of:
- **Installation directory** (`-i`)
- **HTTP port** (`--http-port`)
- **Database user** (`--db-user`)

Example: three active development instances:

```bash
odood init -i odoo-16 -v 16 --db-user=odoo16 --http-port=16069
odood init -i odoo-17 -v 17 --db-user=odoo17 --http-port=17069
odood init -i odoo-18 -v 18 --db-user=odoo18 --http-port=18069
```

Switch between them by changing your working directory:

```bash
cd ~/odoo-16 && odood server start
cd ~/odoo-18 && odood server start
```

## Managing the server

From inside the project directory:

```bash
odood server start      # start Odoo in the background
odood server stop       # stop Odoo
odood server restart    # restart Odoo
odood server status     # check whether Odoo is running
odood server log        # view server log (opens in less)
odood server browse     # open Odoo in the default browser
odood status            # overall status of this instance
```

## Adding third-party repositories

```bash
# Add by full git URL
odood repo add https://github.com/crnd-inc/generic-addons

# GitHub shortcut
odood repo add --github crnd-inc/generic-addons

# OCA shortcut (fetches from github.com/OCA/<name>)
odood repo add --oca web
```

Odood clones the repository into `repositories/<owner>/<name>/` and symlinks all installable addons into `custom_addons/`, making them visible to Odoo automatically.

## Updating Odoo

To update Odoo to the latest available version, run:

```bash
odood venv update-odoo
```

This works for both archive and git-based installations.

## macOS specifics

On macOS the system Python may be incompatible with some Odoo dependencies. Use the `--pyenv` flag to let Odood manage Python via [pyenv](https://github.com/pyenv/pyenv):

```bash
odood init -i odoo-18 -v 18 --pyenv
```

Make sure pyenv is installed and initialised in your shell before running the command.

## Migrating from odoo-helper-scripts

If you have existing Odoo instances that were created with [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/), Odood can import them:

```bash
odood discover odoo-helper
```

Run this command from the root of an odoo-helper-scripts project. Odood will detect the existing configuration and create the `odood.yml` file that it needs to manage the instance.
