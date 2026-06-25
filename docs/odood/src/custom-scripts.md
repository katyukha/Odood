# Custom Scripts

Odood can run custom **Python** or **SQL** scripts against a project's database —
for one-off maintenance, data fixes, or seeding development/test data. There are
two entry points:

- `odood script py` / `odood script sql` — run a script on demand.
- `odood test --script-after-install` / `--script-after-migration` — run scripts
  *during* a test run (see [Development Workflow](./development-workflow.md#running-scripts-around-the-test-cycle)).

Both share the same script types and the same name-resolution rules described
below.

## Running a script

### Python

```bash
odood script py -d <db> <script>
```

The script runs with a full Odoo ORM environment. Available names:

- `env` — the Odoo [Environment](https://www.odoo.com/documentation/master/developer/reference/backend/orm.html#environment);
  e.g. `env['res.partner']`.
- `env.cr` — the database cursor; call `env.cr.commit()` to persist your changes.

Standard Python is available (`import os`, `random`, …). A non-zero exit (an
unhandled exception) fails the command.

```python
# Rename a partner and persist the change.
partner = env['res.partner'].browse(1)
partner.name = "Acme Inc."
env.cr.commit()
```

### SQL

```bash
odood script sql -d <db> <script>
```

Runs raw SQL against the database (multiple statements allowed). The script runs
in a transaction that is committed automatically, unless you pass `--no-commit`
to roll it back (a dry run, useful to preview the effect). SQL is handy to
construct legacy or malformed data states the ORM would not allow.

> **Note:** Odoo's PostgreSQL tables use underscores, not dots — `res_partner`,
> not `res.partner`.

```sql
UPDATE res_partner SET active = true WHERE id = 1;
```

## Where scripts live

You can pass an absolute path, or just a **name** that Odood resolves (in order)
against:

1. `<repo>/.odood-scripts/` — a repository-scoped directory, kept under version
   control alongside your addons. The repo is the one enclosing your current
   directory. Because the file is part of the repo, it is **version-locked** to
   the checked-out ref (this matters for the migration-test hooks).
2. `<project>/scripts/` — a project-level directory in the Odood project root,
   **not** affected by any repository checkout. Good for stable
   maintenance/seeding scripts shared across the project.
3. the current working directory.

So `odood script py -d mydb recompute_totals.py` finds
`.odood-scripts/recompute_totals.py` without a full path. The same resolution
applies to the `--script-after-install` / `--script-after-migration` test hooks.

## Passing parameters with environment variables

Scripts inherit the environment of the `odood` process, so parameters are passed
via **environment variables** — export them before invoking `odood`. A
`ODOOD_SCRIPT_*` prefix is a good convention to avoid collisions. The database
and Odoo serie do not need to be passed in: a Python script already has them from
its `env`.

```bash
ODOOD_SCRIPT_PARTNER_COUNT=50 odood script py -d mydb generate_partners.py
```

### Example: generate random demo data

A script that populates `res.partner` with a configurable number of random
records. `res.partner` is a standard model present in every Odoo edition, which
makes it a safe template — swap the model and fields for your own needs.

```python
# generate_partners.py — create N random res.partner records.
#
# N is read from the ODOOD_SCRIPT_PARTNER_COUNT environment variable
# (default 10), so the same script can generate different amounts:
#
#     ODOOD_SCRIPT_PARTNER_COUNT=50 odood script py -d mydb generate_partners.py

import os
import random
import string

count = int(os.environ.get("ODOOD_SCRIPT_PARTNER_COUNT", "10"))

def _rand(n, alphabet=string.ascii_lowercase):
    return "".join(random.choices(alphabet, k=n))

Partner = env["res.partner"]
for _ in range(count):
    Partner.create({
        "name": "Test Partner " + _rand(6, string.ascii_uppercase),
        "email": "%s@example.com" % _rand(8),
        "phone": "+1-555-%04d" % random.randint(0, 9999),
    })

# Persist the new records.
env.cr.commit()

print("Created %d random res.partner records." % count)
```

Run it against a database, choosing how many records to create:

```bash
# Default (10 records):
odood script py -d mydb generate_partners.py

# 500 records:
ODOOD_SCRIPT_PARTNER_COUNT=500 odood script py -d mydb generate_partners.py
```

If you keep the script in `<repo>/.odood-scripts/` or `<project>/scripts/`, you
can refer to it by name from anywhere in the project.

## Using scripts during tests

The same scripts and resolution rules apply to the test runner's hooks —
`odood test --script-after-install` and `--script-after-migration` — which run a
script after addons are installed and after migrations are applied. This is
commonly used to seed data before a migration test. See
[Development Workflow → Running scripts around the test cycle](./development-workflow.md#running-scripts-around-the-test-cycle).
