# Quick start

## Overview

Odood is Command Line Interface (CLI) tool.
Odood and each subcommand of Odood has option `--help`, thus
if you are interested what it can do, just type `odood --help` :)

## Installation

To install the latest stable version of Odood on Debian/Ubuntu, run:

```bash
wget -O /tmp/odood.deb \
    "https://github.com/katyukha/Odood/releases/latest/download/odood_$(dpkg --print-architecture).deb"
sudo apt install -yq /tmp/odood.deb
```

For macOS, specific versions, and system dependency details, see [Installing Odood](./installation.md).

## Odoo installation

To install Odoo 18 for local development:

```bash
odood init -i odoo-18 -v 18 --db-user=odoo18 --http-port=18069
```

This installs Odoo 18 into the `odoo-18` directory, using a dedicated database user and HTTP port.
For more options and multi-instance setups, see [Local Development](./deployment-local.md).

For Docker Compose or VPS/bare-metal deployments, see the [Deployment Overview](./deployment.md).

## Server management

After installation the following commands are available from inside the project directory:

```bash
odood server start    # start Odoo in the background
odood server stop     # stop Odoo
odood server restart  # restart Odoo
odood server browse   # open Odoo in your browser
odood server log      # view server logs
odood server status   # check if Odoo is running
odood status          # status of this Odoo instance
```

## Database management

Create a test database (name generated automatically):

```bash
odood db create --demo --tdb --recreate
```

Or create a database with a specific name:

```bash
odood db create --demo --recreate my-demo-db
```

List databases:

```bash
odood db list
# shortcut:
odood lsd
```

## Addons management

### Install a third-party addon

Add the repository containing the addon, then install it:

```bash
# Add repository (full URL or GitHub shortcut)
odood repo add https://github.com/crnd-inc/generic-addons
# or:
odood repo add --github crnd-inc/generic-addons
```

Odood clones the repository into `repositories/crnd-inc/generic-addons/` and symlinks all addons to `custom_addons/`, making them visible to Odoo.

Install a specific module into a database:

```bash
odood addons install -d my-demo-db generic_location
```

### Update third-party modules

One of the most frequent tasks is updating third-party modules.
The typical workflow:

```bash
# Change to the repository directory
cd repositories/crnd-inc/generic-addons

# Pull latest changes
git pull

# Relink addons (handles new addons and new Python dependencies)
odood addons link .

# Update all modules in this directory for all databases
# (stops Odoo automatically before update, starts again after)
odood addons update -a --ual --dir .
```

## Running tests

Run tests for a single module on a temporary database:

```bash
odood test -t generic_location
```

Run tests for all installable addons in the current repository directory:

```bash
odood test -t --dir .
```

Odood creates a temporary database, runs the tests with coloured error/warning highlights, then drops the database.
