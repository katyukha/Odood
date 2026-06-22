# Working with Multiple Instances

It is common to run several Odood instances side by side on one machine — for
example one per Odoo series (`16.0`, `17.0`, `18.0`) to develop and forward-port
addons across versions, or several projects on the same series. This page
explains how Odood keeps those instances isolated, how to switch between them,
and how to avoid the port and database conflicts that arise when they share the
same host.

## Each instance is self-contained

An Odood instance is just a project directory. Everything it needs lives inside
that directory and nothing is shared between instances except the host operating
system and the PostgreSQL server:

| Per-instance | Location | Notes |
|---|---|---|
| Configuration | `odood.yml`, `conf/odoo.conf` | Each instance is fully described by its own config files. |
| Python virtualenv | `venv/` | Each series gets its own Python dependencies — never shared. |
| Odoo source | `odoo/` | Independent checkout/install per instance. |
| Addons | `custom_addons/`, `repositories/` | Symlinked addon namespace, isolated per instance. |
| Data & sessions | `data/` | Filestore and sessions per instance. |
| Backups | `backups/` | `odood db backup` writes here. |

See [Directory Structure](./directory-structure.md) for the full layout.

Because an instance carries all of its own state, there is no global "active
project" to configure and no environment to activate — including the virtualenv,
which Odood always invokes from the project's own `venv/` automatically.

## Switching between instances

Odood discovers which instance a command targets by searching for an `odood.yml`
file in the current directory and walking **up** the directory tree until it
finds one. So you switch instances simply by changing your working directory:

```bash
cd ~/odoo-16 && odood server start     # targets the 16.0 instance
cd ~/odoo-18 && odood test -t --dir .  # targets the 18.0 instance
```

Any `odood` command run from inside a project tree (or any subdirectory of it —
for example a repository under `repositories/`) automatically operates on that
instance. There is no `activate`/`deactivate` step and no risk of a command
silently hitting the wrong instance.

> **Note:** If no `odood.yml` is found by walking up from the current directory,
> Odood falls back to the system-wide config at `/etc/odood.yml` (used for
> server-mode deployments). On a developer machine that file usually does not
> exist, so always run instance commands from inside the relevant project tree.

## What must be unique

When several instances run on the same host, three things must differ between
them. `odood init` exposes a flag for each:

| Property | Flag | Why it must be unique |
|---|---|---|
| Installation directory | `-i` / `--install-dir` | Each instance is a separate directory tree. |
| HTTP port | `--http-port` | Only one process can bind a TCP port at a time. |
| Database user | `--db-user` | Determines which databases the instance sees and manages (see below). |

```bash
odood init -i odoo-16 -v 16 --db-user=odoo16 --http-port=16069 --create-db-user
odood init -i odoo-17 -v 17 --db-user=odoo17 --http-port=17069 --create-db-user
odood init -i odoo-18 -v 18 --db-user=odoo18 --http-port=18069 --create-db-user
```

(`--create-db-user` creates the PostgreSQL role if it does not already exist.)

### HTTP and websocket ports

Two instances cannot run concurrently on the same `--http-port`. Pick a distinct
port per instance — encoding the series into the port (`16069`, `17069`,
`18069`) keeps them easy to remember.

If you run an instance with `workers > 0`, Odoo also opens a separate
websocket/longpolling port (Odoo's `gevent_port`, or `longpolling_port` on older
series; default `8072`). In that case set a distinct value in each instance's
`conf/odoo.conf` as well. The default single-process development setup
(`workers = 0`) serves websockets on the main HTTP port, so only `--http-port`
needs attention.

Tests use a separate `conf/odoo.test.conf` with its own port, so you can run
`odood test` in one instance while another instance's server is running.

### Database isolation

All instances share one PostgreSQL cluster, but Odood scopes every database
operation (`odood db list`, `backup`, `drop`, `copy`, …) to the databases
**owned by the instance's configured `db_user`** — it queries PostgreSQL for
databases whose owner is the current role. Giving each instance a distinct
`--db-user` therefore gives each instance its own private view of databases:
instance `odoo16` never lists, backs up, or drops a database created by
`odoo18`.

If two instances share the same `--db-user`, they share a single database
namespace and will see — and can overwrite or drop — each other's databases.
Use a distinct `--db-user` per instance to keep them cleanly separated.

> **Caveat:** A PostgreSQL database name is unique across the whole cluster,
> regardless of owner. Two instances cannot both have a database literally named
> `test` at the same time even with different `db_user`s. In practice you give
> databases distinct names per instance (for example a series prefix), so this
> rarely comes up — but it is why a create can fail with "database already
> exists" even though `odood db list` shows nothing for the current instance.

## Quick reference

To run instances side by side without conflicts, ensure each has:

- a unique installation directory (`-i`),
- a unique HTTP port (`--http-port`) — plus a unique websocket port if using workers,
- a unique database user (`--db-user`), and
- distinct database names.

Everything else — the virtualenv, Odoo source, addons, configuration, data, and
backups — is already isolated per instance by Odood's directory layout.
