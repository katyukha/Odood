# Development Workflow

## Overview

This page describes a recommended workflow for developing Odoo addons in a repository managed alongside Odood.
It covers local testing (including coverage and warnings), translation management, forward-porting across Odoo series,
and CI/CD configuration for both GitHub Actions and GitLab CI.

> **Assumption:** This workflow is designed for *multi-addon repositories* — a single git repository containing
> several related Odoo addons, with one stable branch per supported Odoo series (`17.0`, `18.0`, `19.0`, …).
> This is the standard layout in the Odoo ecosystem, used by OCA and most independent addon vendors.

## Branching Strategy

The recommended branch naming convention mirrors the Odoo series:

- **Stable branch** — `{serie}` (e.g. `18.0`): production-ready code.
- **Development branches** — `{serie}-{feature}` (e.g. `18.0-my-feature`): feature or fix branches.
  CI pipelines are typically triggered on these branches.

## Local Development

### Running Tests

Run tests for a single module on a temporary database:

```bash
odood test -t <module>
```

Run tests for all installable addons in the current directory:

```bash
odood test -t --dir .
```

Odood creates a temporary database, runs the tests, prints a summary with highlighted errors and warnings, then drops the database.

#### Coverage

Odood uses Python's `coverage` tool (installed in the project virtualenv) to measure test coverage.

```bash
# Print a terminal coverage summary after tests
odood test -t --dir . --coverage-report

# Fail if total coverage falls below a threshold (useful in CI)
odood test -t --dir . --coverage-report --coverage-fail-under 90

# Generate an HTML report in htmlcov/ (open htmlcov/index.html in a browser)
odood test -t --dir . --coverage-html
```

`--coverage-report` and `--coverage-html` can be combined in the same command.

#### Warnings report

Odood collects all Odoo log warnings during the test run. To print a deduplicated block of all collected warnings at the end (after the pass/fail summary):

```bash
odood test -t --dir . --warning-report
```

This is useful for spotting deprecation notices or misconfigured modules without having to scan the full test log.

### Migration Tests

Migration tests verify that your addons upgrade correctly from the stable branch to the current development branch.
Odood automates the full cycle: checks out the stable branch, installs modules, optionally populates data, checks out the development branch, and runs the upgrade tests.

Run migration tests for all addons in the current directory:

```bash
odood test -t --migration --dir .
```

> **Note:** Migration tests are expected to be a soft failure in CI.
> They may fail if third-party dependencies introduce changes that are incompatible with the older (stable) version of this repository —
> a situation outside the developer's control.

### Translation Management

See the dedicated [Translation Management](./translations.md) page for the full workflow,
flag reference, and guidance on using AI assistants for translations.

### Module Versioning

Odoo addon versions follow the `A.B.X.Y.Z` scheme, where:

- `A.B` — Odoo series (e.g. `18.0`). Set once when the addon or branch is created; never changed manually.
- `X` — addon major version. Increment for significant data-structure changes that may break backward compatibility.
- `Y` — addon minor version. Increment for noticeable data-structure changes, or whenever a database migration script is required.
- `Z` — addon patch version. Increment for low-risk changes (bug fixes, UI tweaks, new fields that don't require migration).

**Rules of thumb:**
- If you add a migration script → bump at least `Y`.
- If the migration may break backward compatibility → bump `X`.
- Everything else → bump `Z`.

Rather than editing `__manifest__.py` files by hand, you can let Odood bump versions automatically:

```bash
odood repo bump-versions
```

This inspects the git diff, identifies which modules have changed, and increments their patch version (`Z`).
Run it inside the repository directory before committing. For minor or major bumps, adjust the version manually afterwards.

Odood also enforces that every changed module has its version bumped via `odood repo check-versions`.

### Version Checks and Pre-commit

Before pushing, verify that all modified modules have their versions bumped:

```bash
odood repo check-versions --ignore-translations
```

The `--ignore-translations` flag prevents translation-only commits from triggering a version bump requirement.

To run pre-commit hooks (linters, formatters, etc.) locally:

```bash
# First-time setup — installs pre-commit and all hooks into the virtualenv:
odood pre-commit set-up

# Run hooks manually against all staged files:
odood pre-commit run
```

### Per-addon Changelog

To track user-facing changes at the module level, each addon can contain a `changelog/` directory.
Each file inside describes changes introduced in a specific version, using the naming pattern:

```
changelog/
└── changelog.X.Y.Z.md
```

For example, `changelog/changelog.1.3.0.md` contains a markdown description of what changed in version `1.3.0` of that addon.

The file content is free-form markdown — describe what changed from an end-user perspective, not implementation details.

Odood reads these files when generating the assembly-level changelog.
When you run `odood assembly sync --changelog`, it aggregates per-addon changelogs across all updated modules into a single `CHANGELOG.md` (and `CHANGELOG.latest.md`) at the assembly root — useful for release notes and communicating changes to end users.

### Releasing a Repository

Once your changes are committed and versions are bumped, cut a release with
`odood repo release`. The full release strategy — version conventions, the
standard release flow, the hotfix flow, and CI setup — is documented on a
dedicated page: **[Release Management](./release-management.md)**.

In short:

```bash
# Auto-detect the bump level from changed addons, verify versions,
# generate the changelog, tag, and push:
odood repo release --changelog --push

# First release of a never-tagged repository:
odood repo release --initial
```

To patch an already-released version while the stable branch has moved on, use
the hotfix flow (`odood repo hotfix`) — see
[Release Management → Hotfix flow](./release-management.md#hotfix-flow).

---

## Forward-porting

When you maintain addons across multiple Odoo series (e.g. 17.0 and 18.0), development typically happens on the oldest supported series first, and the resulting changes are then forward-ported to newer series.

For example, you develop a fix on `17.0`, then need to carry it into `18.0` and `19.0`.
The naive approach — manually cherry-picking or re-applying changes — is tedious because:

- Module versions embed the series prefix and must be updated (e.g. `17.0.1.2.3` → `18.0.1.2.3`).
- Migration script directories also embed the series (e.g. `migrations/17.0.1.2.3/` → `migrations/18.0.1.2.3/`).
- Translation files in the target branch should be kept as-is — conflicts in `.po`/`.pot` files are meaningless and always resolved in favour of the target branch.

`odood repo do-forward-port` automates all of this, leaving only genuine business-logic conflicts for you to resolve manually.

### Workflow

1. Switch to your Odoo environment for the **target** series (e.g. your `18.0` project).
2. Change into the repository directory.
3. Create (or check out) a forward-port branch:
   ```bash
   git checkout -b 18.0-forward-port-<feature>
   ```
4. Run the forward-port command, naming the **source** series:
   ```bash
   odood repo do-forward-port -s 17.0
   ```
   The command will automatically:
   - Fetch `origin/17.0` and open a merge (`--no-ff --no-commit`) into the current branch, staging all changes for review.
   - Reset `.po`/`.pot` files to the target-branch version — translation conflicts are always discarded.
   - Fix version number conflicts in each addon's `__manifest__.py`, rewriting the series prefix.
   - Rename migration script directories from the source series to the target series (e.g. `migrations/17.0.1.2.3/` → `migrations/18.0.1.2.3/`).

5. Resolve any remaining merge conflicts (business logic, structural changes, etc.).
6. Run tests to verify everything works in the target series:
   ```bash
   odood test -t --dir .
   ```
7. Commit and push:
   ```bash
   git push origin 18.0-forward-port-<feature>
   ```
8. Open a pull/merge request into the `18.0` stable branch and wait for CI to pass.
9. Repeat steps 1–8 for each remaining target series (`19.0`, etc.).

> **Note:** `do-forward-port` is currently marked experimental.
> In straightforward cases (no structural conflicts) it produces a ready-to-commit merge with zero manual intervention.

---

## CI/CD Configuration

### Key concept: `--config-from-env` and `ODOOD_OPT_*`

The prebuilt Docker images already have Odoo installed and ready. Two variants are published per serie:

- `ghcr.io/katyukha/odood/odoo/{serie}:latest` — the production image (includes a container `HEALTHCHECK`).
- `ghcr.io/katyukha/odood/odoo-ci/{serie}:latest` — the **CI image**, recommended for test/lint jobs (see [the CI image](#key-concept-the-ci-image) below).

`ODOOD_OPT_*` environment variables allow you to override individual Odoo configuration options (i.e. values in `odoo.conf`) at runtime — without modifying any file on disk.
Combined with the `--config-from-env` flag, this is the standard way to point CI containers at the PostgreSQL sidecar.

> **Note:** The `--config-from-env` flag and `ODOOD_OPT_*` support are only compiled in when Odood is built
> with the `-d-version OdoodInDocker` flag, and thus are available only in the official prebuilt Docker images.
> The Debian package and source builds do not include this flag.

For example, set these environment variables in your CI job:

```
ODOOD_OPT_DB_HOST=postgres
ODOOD_OPT_DB_USER=odoo
ODOOD_OPT_DB_PASSWORD=odoo
```

Then invoke Odood as:

```bash
odood --config-from-env addons link .
odood --config-from-env test -t --dir .
```

#### Common `ODOOD_OPT_*` variables

Each variable maps directly to the corresponding key in Odoo's `[options]` section of `odoo.conf`.
The prefix `ODOOD_OPT_` is stripped and the remainder is lowercased before being applied.

| Environment variable | `odoo.conf` key | Description |
|---|---|---|
| `ODOOD_OPT_DB_HOST` | `db_host` | PostgreSQL host |
| `ODOOD_OPT_DB_PORT` | `db_port` | PostgreSQL port (default: `5432`) |
| `ODOOD_OPT_DB_USER` | `db_user` | PostgreSQL user |
| `ODOOD_OPT_DB_PASSWORD` | `db_password` | PostgreSQL password |
| `ODOOD_OPT_ADMIN_PASSWD` | `admin_passwd` | Odoo master password (database manager) |
| `ODOOD_OPT_WORKERS` | `workers` | Number of worker processes (`0` = single-process mode) |
| `ODOOD_OPT_PROXY_MODE` | `proxy_mode` | Set `True` when running behind a reverse proxy |
| `ODOOD_OPT_DBFILTER` | `dbfilter` | Regex to restrict which databases are served |
| `ODOOD_OPT_LIMIT_MEMORY_HARD` | `limit_memory_hard` | Hard memory limit per worker (bytes) |
| `ODOOD_OPT_LIMIT_MEMORY_SOFT` | `limit_memory_soft` | Soft memory limit per worker (bytes) |
| `ODOOD_OPT_LIMIT_TIME_CPU` | `limit_time_cpu` | CPU time limit per request (seconds) |
| `ODOOD_OPT_LIMIT_TIME_REAL` | `limit_time_real` | Real time limit per request (seconds) |
| `ODOOD_OPT_LOG_LEVEL` | `log_level` | Log level (`info`, `debug`, `warning`, `error`) |

Any other valid `odoo.conf` option can be set the same way — the list above covers the most commonly needed ones in containerised deployments.

For deployment context (not CI), see [Docker Compose deployment](./deployment-docker-compose.md).

---

### Key concept: the CI image

The `odoo-ci/{serie}` image is a drop-in CI variant of the production image (same
`--config-from-env` / `ODOOD_OPT_*` mechanism), used by the examples below. It differs in two ways:

- **No `HEALTHCHECK`** — the container is a disposable test runner, not a server.
- **Dev/test tooling pre-installed** (`odood venv install-dev-tools`): `pre-commit`, `eslint`,
  `flake8`, `pylint-odoo`, `coverage`, etc. — so lint and coverage jobs don't reinstall it each run.

> **Tip:** `pre-commit` is baked in, but its hook environments are still built from your repo's
> `.pre-commit-config.yaml` on first run — cache `~/.cache/pre-commit` between runs.

---

### GitHub Actions

The following workflow runs on development branches (`18.0-*`).
It has three jobs: **lint** (runs first), then **tests** and **migration-tests** in parallel.

```yaml
name: Tests
on:
  push:
    branches:
      - '18.0-*'

jobs:
  lint:
    name: Lint & version checks
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/katyukha/odood/odoo-ci/18.0:latest
    steps:
      - uses: actions/checkout@v4

      - name: Add repo as git safe directory
        run: git config --global --add safe.directory "$(pwd)"

      - name: Link addons
        run: odood --config-from-env addons link .

      - name: Add dependencies
        run: odood --config-from-env addons add --single-branch --odoo-requirements ./odoo_requirements.txt

      - name: Check versions
        run: odood --config-from-env repo check-versions --ignore-translations

      - name: Install pre-commit
        run: odood --config-from-env pre-commit set-up

      - name: Run pre-commit
        run: odood --config-from-env pre-commit run

  tests:
    name: Tests
    runs-on: ubuntu-latest
    needs: lint
    container:
      image: ghcr.io/katyukha/odood/odoo-ci/18.0:latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: odoo
          POSTGRES_PASSWORD: odoo
          POSTGRES_DB: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      ODOOD_OPT_DB_HOST: postgres
      ODOOD_OPT_DB_USER: odoo
      ODOOD_OPT_DB_PASSWORD: odoo
    steps:
      - uses: actions/checkout@v4

      - name: Add repo as git safe directory
        run: git config --global --add safe.directory "$(pwd)"

      - name: Link addons
        run: odood --config-from-env addons link .

      - name: Add dependencies
        run: odood --config-from-env addons add --single-branch --odoo-requirements ./odoo_requirements.txt

      - name: Run tests
        run: odood --config-from-env test -t --dir .

  migration-tests:
    name: Migration Tests
    runs-on: ubuntu-latest
    needs: lint
    # Migration tests may fail if dependencies introduce incompatible changes
    # with an older version of this repo — treated as a soft failure.
    continue-on-error: true
    container:
      image: ghcr.io/katyukha/odood/odoo-ci/18.0:latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: odoo
          POSTGRES_PASSWORD: odoo
          POSTGRES_DB: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      ODOOD_OPT_DB_HOST: postgres
      ODOOD_OPT_DB_USER: odoo
      ODOOD_OPT_DB_PASSWORD: odoo
    steps:
      - uses: actions/checkout@v4

      - name: Add repo as git safe directory
        run: git config --global --add safe.directory "$(pwd)"

      - name: Link addons
        run: odood --config-from-env addons link .

      - name: Add dependencies
        run: odood --config-from-env addons add --single-branch --odoo-requirements ./odoo_requirements.txt

      - name: Run migration tests
        run: odood --config-from-env test -t --migration --dir .
```

> **Tip:** If your addons have no third-party dependencies, you can omit the "Add dependencies" step and the `odoo_requirements.txt` file.

---

### GitLab CI

The following pipeline mirrors the GitHub Actions structure using GitLab CI's `extends` keyword to share the common setup.

```yaml
image: ghcr.io/katyukha/odood/odoo-ci/18.0:latest

stages:
  - lint
  - test

# Shared setup: link addons and fetch dependencies.
# Requires odoo_requirements.txt at repo root; remove the second line if not needed.
.setup:
  before_script:
    - git config --global --add safe.directory "$(pwd)"
    - odood --config-from-env addons link .
    - odood --config-from-env addons add --single-branch --odoo-requirements ./odoo_requirements.txt

# Shared PostgreSQL sidecar and matching ODOOD_OPT_* variables.
.with-postgres:
  services:
    - name: postgres:15
      alias: postgres
  variables:
    POSTGRES_USER: odoo
    POSTGRES_PASSWORD: odoo
    POSTGRES_DB: postgres
    ODOOD_OPT_DB_HOST: postgres
    ODOOD_OPT_DB_USER: odoo
    ODOOD_OPT_DB_PASSWORD: odoo

lint:
  extends: .setup
  stage: lint
  script:
    - odood --config-from-env repo check-versions --ignore-translations
    - odood --config-from-env pre-commit set-up
    - odood --config-from-env pre-commit run

tests:
  extends:
    - .setup
    - .with-postgres
  stage: test
  script:
    - odood --config-from-env test -t --dir .

migration-tests:
  extends:
    - .setup
    - .with-postgres
  stage: test
  only:
    - /^18\.0-.*$/
  script:
    # Migration tests may fail if dependencies introduce incompatible changes
    # with an older version of this repo — treated as a soft failure.
    - odood --config-from-env test -t --migration --dir .
  allow_failure: true
```

> **Note:** Adjust the Odoo series (`18.0`) in the image tag and the `only` regex to match your project's series.
