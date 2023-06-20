# Changelog

## Release 0.0.10 (Unreleased)

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
