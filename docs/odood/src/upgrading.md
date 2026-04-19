# Upgrading Odoo

This page covers how to update Odoo and third-party addons in an existing Odood-managed instance.

## Before you upgrade

Always back up your databases before any upgrade or configuration change:

```bash
# Back up all databases
odood db backup -a

# Or back up a single database
odood db backup -d mydb
```

On a production server, prefix with `sudo`.

## Updating Odoo itself (same series)

To update Odoo to the latest available revision of the current series (e.g., 18.0.x → latest 18.0):

```bash
odood venv update-odoo
```

This works for both archive-based and git-based installations.
After updating Odoo, restart the server and update your installed addons (see below).

On a production server:

```bash
sudo odood venv update-odoo
```

## Updating third-party addons

### With assembly (recommended for production)

If the instance is configured to use [Assembly](./assembly.md), a single command handles everything:

```bash
odood assembly upgrade
```

With an automatic pre-upgrade backup of all databases:

```bash
odood assembly upgrade --backup
```

This pulls the latest assembly, relinks addons, and updates all addons in all databases.
On a production server, prefix with `sudo`.

### Without assembly

If you manage third-party repositories directly, follow this sequence:

```bash
# 1. Stop the server
odood server stop

# 2. Pull latest changes from all cloned repositories
odood repo pull-all

# 3. Refresh the addon list
odood addons update-list

# 4. Update addons — list every affected repository with --dir
odood addons update --dir repositories/vendor1/repo1 --dir repositories/vendor2/repo2

# 5. Start the server
odood server start
```

**Why stop the server first?** Running old and new code simultaneously during an upgrade
can corrupt data or leave modules in an inconsistent state.
Stop the server, apply the updates, then restart.

**Why use `--dir` and not the web UI?** CLI updates run to completion before any HTTP
request can touch the upgraded models. Web-triggered upgrades can break mid-way if a
model change makes the active session invalid, leaving the database in a broken state.

**Updating all repositories at once**: if your addons span multiple repositories and
have cross-repo dependencies, pass a `--dir` flag for each affected repository so Odoo
resolves the dependency graph in a single pass.

**Check all databases**: if you have multiple databases on this instance, run the update
for every database that has the affected addons installed — not just the primary one.
`odood addons update --dir ...` updates all databases by default; use `-d mydb` to
restrict to a specific one if you intentionally want to skip others.

After the server restarts, verify that the web UI is accessible and that Odoo
started without errors before calling the upgrade done.

## Full local development upgrade flow

A typical update session on a developer machine:

```bash
# Pull all repo updates
odood repo pull-all

# Refresh addon list and update all addons in the active database
odood addons update-list
odood addons update --dir custom_addons

# Or update only addons you changed
odood addons update my_addon another_addon
```

Local development instances don't need the stop/start ceremony — the server restarts
automatically when you run `odood addons update`.
