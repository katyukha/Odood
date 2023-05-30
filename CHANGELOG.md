# Changelog

## Release 0.0.9 (unreleased)

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
