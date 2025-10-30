# Changelog

## Release 0.5.1

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
