# Changelog

## Unreleased

### Added

- Support for `--test-tag` option for `odood test` command
- **Experimental** `odood repo release` command, that could automatically tag repo and generate changelogs.
- **Experimental** `odood assembly upgrade-sources` command, that  allows to bump pinned releases on repository.

### Changed

- Switched to [DarkCommand](https://code.dlang.org/packages/darkcommand) CLI lib:
    - better autocomplete (file paths when needed)
    - better automatic documentation (CLI Ref)

### Fixed

- Run `msguniq` before `msgmerge` when regenerating translations,
  because AI too frequently generate duplicateg translatios and `msgmerge` fails
- Use `data_dir` from `odoo.conf` for backup/restore to ensure backups are correct when `data_dir` changed to non-standard location.
  Before fix, it was required to modify data dir on both places: `odood.yml` and `odoo.conf`

---

## Release 0.6.2 (2026-05-09)

### Added

- Added new documentation on assembly spec
- Updated assembly documentation with more examples

### Fixed

- Correct handling of `no-search` param on assembly spec.


---

## Release 0.6.1 (2026-04-20)

### Added

- Batch Python requirements installation: when linking addons (via `odood addons link`,
  `odood assembly link`, or `odood venv reinstall`), all Python requirements are now
  gathered and installed in a single `pip install` call instead of one call per addon.
  This improves performance and lets pip resolve the full dependency tree at once.
    - New flag `--individual-requirements` for `odood addons link` and `odood assembly link`
      to fall back to per-addon installation (old behavior).
    - New flag `--with-odoo-requirements` for `odood addons link` and `odood assembly link`
      to include Odoo's own `requirements.txt` in the batch install.
- Assembly requirements lock file support: if `requirements.lock.txt` exists in the
  assembly root, `odood assembly link` installs only from that file and skips per-addon
  requirement scanning. This gives assembly maintainers full control over the Python
  dependency tree for reproducible deployments.
    - New flag `--generate-lock` for `odood assembly sync` to generate the lock file
      after syncing (runs `pip freeze` to produce pinned versions).
    - New flag `--with-odoo-requirements` for `odood assembly sync` to include Odoo's
      requirements when generating the lock file.
- New flag `--odoo-helper-compat` for `odood pre-commit init` that generates a
  pre-commit config compatible with odoo-helper-scripts' default linting style
  (check-only — no auto-formatting). Useful for migrating projects from odoo-helper.
    - Added bandit security scanner hook to the default pre-commit config.
    - Added `odoolint` catchall check to the default pylintrc
- Added support for commit pinning on the assembly spec
- Added `--log-to-stderr` flag to `odood init` (mirrors `odood deploy`): initialises
  the project without a log file so all Odoo output goes to stderr/stdout.
  Recommended for container deployments.
- Odoo stderr is now forwarded to the caller during addon install/update and
  database initialisation when no logfile is configured.
- Added ability to restore backup into empty but existing database. Useful in container environments.

### Changed

- Tests now use os-provided available tcp ports to run Odoo,
  thus it is possible to run few different tests with different databaes in parallel
- `odood venv reinstall` now installs all addon Python requirements in a single
  batched pip call instead of one per addon.
- Switched to `darkarchive` lib to handle archives.
  Thus, backups do not require temporary files anymore, and could be done in more space-eficient way.

---

## Release 0.6.0 (2026-03-11)

### Added

- Added `odood server healthcheck` command. One step to make Odood container-friendly.
- Added `odood server wait-pg` command
- Added `odood server run --wait-pg` option
- Added `odood db is-initialized` command to check if database is already initialized.
- Added `odood db ensure-initialized` command to  initialize database if it is not initialized yet.
- Added new options to `odood addons install`
    - `--missing-only` - install only addons that are not installed in specified db from the list.
    - `--ignore-unfinished-updates` - do not fail on unfinished updates
- Added new options to `odood addons update`
    - `--installed-only` - install only addons that are not installed in specified db from the list.
    - `--ignore-unfinished-updates` - do not fail on unfinished updates
- Added `--tls12-compat` flag to `odood deploy` to allow TLS 1.2 in addition
  to TLS 1.3 for backward compatibility with older clients.
- Added `--use-system-ca-bundle` flag to `odood deploy` to set
  `REQUESTS_CA_BUNDLE` to the system CA certificate store. Auto-detects
  the CA bundle path across Debian/Ubuntu, RHEL/CentOS/Fedora, and openSUSE.



### Changed

- Changed template for `nginx` configuration for `deploy` command:
    - Added security headers
    - Database manager (`/web/database`) is blocked by default
    - Bugfixes related to nginx config generation
- Nginx SSL configuration now defaults to TLS 1.3 only with hardened cipher
  suites (FIPS 140-2/3 compliant, no CBC/RC4/3DES). Use `--tls12-compat`
  to enable TLS 1.2 with ECDHE forward secrecy ciphers.
- Command `odood db list` rewritten in D (no more python / lodoo call)
- Commands `odood addons install` and `odood addons update` now will
  fail if there are unfinished addon updates before running command or after.
  This way these commands ensures clean state of db before and after operation.
- Default dockerimage's command now waits when pg is ready before running Odoo (`odood server run --wait-pg` insteand of `odood server run`)
- "No access rules" warnings are no longer treated as test errors. Models
  that intentionally have no ACLs (e.g. sudo()-only technical models) will
  no longer cause `odood test` to fail.


### Fixed
- Odood now will handle `db_sslmode` parameter correctly inside it's internal database interactions

---

## Release 0.5.5 (2026-02-25)

### Added

- New command `odood venv lodoo` that exposes [LOdoo](https://pypi.org/project/lodoo/) bundled to current project.

### Fixed

- Fixed bad dependency on `cbor==5.4.2`. Patch the requirements.txt during Odoo installation.

---

## Release 0.5.4 (2026-02-06)

### Added

- Assemblies:
    - added support for `known-addons` key in spec
    - added support for assembly layout config (standard and flat)
    - added support for downloading addons from Odoo Apps
    - Clone/update git sources in parallel
    - Added assemply spec validation before sync operation
    - Added new option `--dockerfile` that allows to automatically generate Dockerfile for assembly on *sync*.
      Thus we have the way to build standard images for assemblies.
- Added ability to pull all repositories via command `odood repo pull-all`.
  This could be helpfull during development to pull all repos on instance.
- Added command `odood pre-commit update` that could be used to update pre-commit dependencies (in pre-commit config).
  Just an alias for standard `pre-commit autoupdate` that is run inside correct repo dir and within correct venv.
- Added option `--workers` to `deploy` command

### Changed

- Clean up pip cache after deploy, when docker image is built.
- Assembly, if `VERSION`, `Dockerfile` or `.dockerignore` changed, that commit of changes allowed.

---

## Release 0.5.3 (2026-01-08)

### Added

- Build docker images for ARM64 architecture
- New option to `assembly upgrade` command:
   - `--start` - automatically start server if upgrade is successful and server was not running before upgrade.
- Added new option `odood assembly --assembly-path` that could be used to specify different assembly path for assembly commands.
  Mostly, this option could be useful for CI

### Changed

- Now, when assembly contains `requirements.txt` file, it will be processed automatically before assembly link operation.

---

## Release 0.5.2 (2025-12-23)

### Added

- Added option `--start` to `addons install/update/uninstall` command to automatically start server if it was stopped.
- Added automatic generation of changelogs on `assembly sync` if option `--changelog` specified.
  If enabled, then Odood will automatically generate VERSION file for assembly repo. It could be used later to track versions of assemblies.

### Changed

- Database populatation now works only for Odoo version 14-17, because starting from Odoo 18 population means duplication instead of generation.
- After backup of database completed, log message about backup completed and duration of operation.

### Fixed

- Fixed bug with false-positives in when running migration tests on new addons.

---

## Release 0.5.1 (2025-11-02)

### Added

- Experimental support for Odoo 19
- Experimental support for deployment with let's encrypt certs.

---

## Release 0.5.0 (2025-09-12)

### Added

- New options to `odood deploy` command:
  - `local-nginx-ssl` to enable SSL configuration for local nginx
  - `local-nginx-ssl-key` choose path to ssl key for the server
  - `local-nginx-ssl-cert` choose paht to ssl certificate for the server
- Git sources in assembly spec now supports shortucts `github` and `oca` that allows to simplify configuration of git sources
- During assembly sync, Odood can automatically apply acccess credentials from env variables:
  - For named sources `ODOOD_ASSEMBLY_repo_name_CRED`
  - Added support for access groups (`access-group` for sources in `odood-assembly.yml`), this way it is possible to use same token for multiple repos.
    The name is `ODOOD_ASSEMBLY_access_group_CRED`
  - The format of `ODOOD_ASSEMBLY_<group/repo>_CRED` variable is `username:password`
- During assembly upgrade, check for unfinished install/upgrade and print waring if there are any unfinished install/upgrade/uninstall
- Added new option `assembly-repo` for `odood deploy` command, that allows to automatically configure deployed instance to use specified assembly.

---

## Release 0.4.4 (2025-08-03)

### Added
- Automatic check for missing dependencies of assembly addons on *assembly sync*.
- Ability to use existing assembly for project via `odood assembly use` command.
  This could be useful in CI to automate assembly sync process.
- Added new options to specify commit params for `odood assembly sync` command.
- Added experimental `odood repo do-forward-port` command

### Changed
- `odood log` now will automatically show the end of logfile

---

## Release 0.4.3 (2025-07-05)

### Added
- Addd new command `odood repo migrate-addons` that uses *under the hood* OCA's utility [odoo-module-migrator](https://github.com/OCA/odoo-module-migrator/) to migrate source code of modules to project's serie from older odoo series.

### Fixes
- Fix installation of odoo on Ubuntu 22.04 because of non-recent setuptools and recent update of zope.event.

---

## Release 0.4.2 (2025-06-21)

### Fixes
- Fix handling of check if nginx is installed on Ubuntu 22.04

---

## Release 0.4.1 (2025-06-20)

### Added

- New command `odood repo check-versions` that could be used to check if module versions updated.
- New option `--lang` to `odood translate regenerate` command.
  With this option, translation file will be detected automatically.
- New option `--repeat` to `odood db populate` command, that allow to repeat database population N times.
- Added new command `odood assembly upgrade`, that could be used to upgrade assembly in single command, that includes:
   - optionally, take backup before any other step
   - pull latest changes
   - relink assembly addons
   - update all assembly addons for all databases available on managed instance

---

## Release 0.4.0 (2025-05-29)

### Added

- New command `odood db populate` that allows to populate database with test data
- New options to `odood test` command (`--populate-model` and `--populate-size`)
  that could be used to populate database with test data before running tests.
  Especially, this could be useful for migration tests
- New command `odood assembly` that could be used to manage Odoo instance in assembly style,
  when all addons used on instance are placed in single repo.
- Added new flag `--assembly` to `odood addons list/update/install/uninstall` commands

### Changed

- Command `odood odoo recompute` - changed parameters:
    - use options instead of arguments
    - allow to run for multiple databases (or for all databases)
- Command `odood db list-installed-addons` renamed to `odood addons find-installed`.
- Command `odood addons find-installed` got new options:
    - `--non-system` - output only non-system addons (that are not included in official Odoo community)
    - `--format` - what format to use for output: list, assembly-spec

---

## Release 0.3.1 (2025-04-23)

### Added

- Support and release for arm64 architecture
- Added new command `repo bump-versions` to automatically bump versions of modules
- Added new options for `odood deploy` command:
    - `--local-nginx` that allows to automatically configure local nginx (requires nginx installed)
    - `--enable-fail2ban` that allows to automatically configure fail2ban for Odoo (required fail2ban installed)

### Removed

- Dropped support for **Ubuntu: 20.04** (compile release for Ubuntu 22.04+)
- Dropped support for **Debian: Bullseye** (compile release for Debian bookworm+)

---

## Release 0.3.0 (2025-03-14)

### Added

- New command `odood translations regenerate` that allows to regenerate translations for modules.
  Could be useful to automatically or semiautomatically generate `.po` and `.pot` files for modules.
  Also, this command available as shortcut `odood tr regenerate`.
- New flag `--no-install-addons` added to `odood test`.
  It could be used to speed up running tests on localc machine on same db.

### Changed

- **Breaking** Changed approach to docker images. No more custom entry point.
  Just single option (on application level), that allows to update Odoo configuration from environment variables.
  Default command uses this option. but custom commands will need to use this option.
  Currently, this requires explicit specification of this command on Odood runs.
  This may be changed in future.
- **Breaking** Do not use separate config file for tests on deployments (Odoo installations installed via `odood deploy` command)

---

## Release 0.2.2 (2025-03-10)

### Added

- Experimental support for [PyEnv](https://github.com/pyenv/pyenv) integration.

### Changed

- Replace [dpq](https://code.dlang.org/packages/dpq) with [Peque](https://code.dlang.org/packages/peque)
- `odood script py` command: now output of script will be redirected on stdout.
   Thus no more need to wait while script completed to get intermediate output of script.


---

## Release 0.2.1 (2025-01-23)

### Changed

- Added new command `entrypoint` that is available only in version for docker images,
  that is used as *entrypoint* for docker container and that is responsible for applying
  configuration from environment variables to Odoo configuration file before
  any further action.
- Added new command `odood odoo recompute` that allows to recompute computed fields for specified model in specified database.


---

## Release 0.2.0 (2024-12-12)

### Added

- New experimental command `odood deploy` that could be used to deploy production-ready Odoo instance.
- Added experimental support for Odoo 18
- Added new command `odood repo fix-series` that allows to set series for all modules in repo to project's serie.
- Added automatic builds of docker images with pre-installed Odoo.

### Changed

- Pre-commit related commands moved to `pre-commit` subcommand.
  Thus, following commands now available to work with pre-commit:
    - `odood pre-commit init`
    - `odood pre-commit set-up`
    - `odood pre-commit run`
- Change command `odood server run`. Command uses `execv` to run Odoo,
  thus, Odoo process will replace Odood process. Thus, option `--detach`
  is not available here. If you want to start Odoo in background, then
  `odood server start` command exists. Instead, this command (`odood server run`)
  is designed to run Odoo with provided args in same way as you run Odoo binary directly.
  For example, following command
  `odood server run -- -d my_database --install=crm --stop-after-init`,
  that will install `crm` module, will be translated to `odoo -d my_database --install=crm --stop-after-init`,
  that will be ran inside virtualenv of current Odood project.
    - Added new option `--ignore-running` that allows to ignore server running.
    - Removed option `--detach` as it does not have sense. Use `odood server start` instead.
- Changed generation of default test db name.
  Before it was: `odood<serie>-odood-test`
  Now it will be: `<db_user>-odood-test`

---

## Release 0.1.0 (2024-08-15)

### Added

- New command `odood venv pip` that allows to run pip from current venv.
- New command `odood venv npm` that allows to run npm from current venv.
- New command `odood venv python` that allows to run python from current venv.
- New command `odood venv ipython` that allows to run ipython from current venv.
- Added new option `--ual` to command `odood repo add` that allows to automatically
  update list of addons when repository was added.
- New command `odood venv run` that allows to run any command from current venv.
- New command `odood repo run-pre-commit` to run [pre-commit](https://pre-commit.com/) for the repo.

### Changed

- Database restoration reimplemented in D,
  thus now it restores db dump and filestore in parallel.

---

## Release 0.0.15 (2023-10-30)

### Added

- Added ability skip addons specified in file during install/update/upgrade.
- Added new options to `odood test` command:
    - `--file` that could be used to pass the path to file to read addons to test from
    - `--skip-file` read names of addons to skip from file

### Changed

- Installation of dependencies from manifest is now optional.
  It is frequent case, when authors of module place incorrect dependencies
  in manifest, thus installation of addon may fail.

### Fixes

- Fix error when running `addons install/update/uninstall` with non-existing
  logfile. This was caused by attempt to determine starting point of logfile
  to search for errors happened during operation.
  Now this case is handled correctly.

---

## Release 0.0.14 (2023-10-04)

### Added
- Added new options `--skip` and `--skip-re` to `odood test` command,
  that allow to not run tests for specified addons.
  Useful in cases, when there is need to skip some addons
  found via options `--dir` and `--dir-r`
- Added new options `--skip` and `--skip-re` to `odood addons install/update/uninstall` commands.
  Useful in cases, when there is need to skip some addons
  found via options `--dir` and `--dir-r`
- Added new option `--skip-errors` to `odood addons install/update/uninstall` commands, that allows
  to not fail when installing addons in database,
  thus allowing to install addons to other databases, and fail in the end.
- Added new option `--install-type` to `odood init` and `odood venv reinstall-odoo` commands,
  thus, now it is possible to install Odoo as git repo or as unpacked archive depending on this option

### Changed
- Load Python dynamically, thus make Odood more portable.
- Finally, make Odood portable. Now we have universal deb package, that could be installed on most debian-based repos newer then ubuntu:20.04
- Commands `odood addons install/update/uninstall` now will report Odoo errors raised during addons installation.

---

## Release 0.0.13 (2023-09-08)

### Added

- Command `odood addons generate-py-requirements` that allows to generate
  requirements txt files for specified modules.
- Added new option `--tdb` to `odood db create` command,
  that allows to use automatically generated default name for tests database.
- Added new command `odood db list-installed-addons`.
  This command could be used to print to stdout or
  file list of addons installed on specific databases.

---

## Release 0.0.12 (2023-08-14)

### Added

- Command `odood odoo shell` that allows to open odoo shell for specified db.
- Added release for `debian:bullseye`

### Changed

- Implement backup of database on D level. This way it provides better error handling.
- Added ability to cache downloads if `ODOOD_CACHE_DIR` environment variable is set.

---

## Release 0.0.11 (2023-07-27)

### Added

- New option `--simplified-log` added to `odood test` command.
  Thus it is possible to display meaningful log info (log level, logger, message).

### Changed

- Command `odood venv reinstall-odoo` now backups old odoo by default.
  But it is possible to disable backup with option `--no-backup`
- Now it is allowed to specify only name of backup to restore database from.
  In this case, Odood will try to find corresponding backup in standard
  backups directory of project.

### Fixed

- Correctly handle `--additional-addons` passed for tests
  in case when migration test enabled: update that addons before running tests.

---

## Release 0.0.10 (2023-07-08)

### Added

- New option `--all` to `odood db backup` command, that allows to backup
  all databases within single command.
- New command `info` that will display info about project,
  optionally in JSON fromat.
- New option `--file` to `odood addons install` and `odood addons update`
  commands. This option allows to get list of addons to install / update
  from provided file. This way, it is possible to avoid specifying list of
  addons manually.
- New option `--install-file` to `odood db create` command, that
  will automatically install modules from specified files.
- New option `--coverage-ignore-errors` to `odood test` command, that allows
  to ignore coverage errors, that a frequent case during migration tests
  (because files available on start may disapear during migration).
- New option `--recreate` to `db restore` command, thus it is possible
  to automatically drop database before restoration if needed.
- Added flag `--backup` to `venv update-odoo` command.
- Added new command `odood venv reinstall-odoo`, that could be used to
  reinstall odoo to different version in same venv.
  This could be used for migrations to avoid the need to setup new machine
  for migrated instance.

### Changed

- Command `odood db backup`: when `--dest` option supplied and
  it is existing directory, then database will be backed up in this directory
  with automatically generated name of backup.
- Automatically supply `--ignore-errors` to `coverage` when running migration
  tests

---

## Release 0.0.9 (2023-06-01)

### Added

- New option `--ual` to `odood addons install` and `odood addons update` comands
- New option `--additional-addon` to `odood test` command
- New options for `odood addons list` command:
    - `--with-price` and `--without-price` for `odood addons list` command
    - `--color=price` to highlight addons that have or have no prices
    - `--table` to output list of addons as table
- New command `odood venv install-py-packages` that could be used to easily
  install python packages in Odood virtualenv environment
- New option `--warning-report` to `odood test` command:
  if this option provided, then Odood will print uniq list of warnings
  in the end of test run

---

## Release 0.0.8 (2023-05-05)

### Added

- Add new option --color=installable to addons list command
- Added command `odood ci fix-version-conflict` to resolve version conflicts
  in module manifests

### Changed

- `odood test` command: show error report by default, but add option to
  disable it.
- Clone repos recursively optionally. Before this change,
  command `odood repo add` was clonning repositories recursively
  (parse `odoo_requirements.txt` file in clonned repo and clone dependencies
  mentioned there). After this change, recursive add repo is optional,
  end could be enable by option `odood repo add --recursive ...`
- `odoo test` with option `--isw` will additionally ignore following warning:
  `unknown parameter 'tracking'`

---
