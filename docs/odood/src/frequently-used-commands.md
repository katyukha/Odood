# Frequently used commands

Short list of frequently used Odood commands

### Server management
- `odood start` - start odoo server
- `odood restart` - restart odoo server
- `odood stop` - stop odoo-helper server
- `odood log` - see odoo server logs
- `odood browse` - open running odoo installation in browser

### Addons management
- `odood addons list <path>` - list odoo addons in specified directory
- `odood addons update-list` - update list of available addons in all databases available for this server
- `odood addons install <addon1> [addonN]` - install specified odoo addons for all databases available for this server
- `odood addons update <addon1> [addonN]` - update specified odoo addons for all databases available for this server
- `odood addons uninstall <addon1> [addonN]` - uninstall specified odoo addons for all databases available for this server
- `odood addons update --dir <path>` - find all installable addons in specified directory and update them
- `odood addons install --dir <path>` - find all installable addons in specified directory and install them
- `odood addons link .` - link all addons in current directory.
- `odood addons add -h` - add third-party addons from [odoo-apps](https://apps.odoo.com/apps) (free only) or from [odoo-requirements.txt](./odoo-requirements-txt.md)

### Tests
- `odoo-helper test -t <module>` - test single module on temporary database
- `odoo-helper test -t --dir .` - test all installable addons in current directory
- `odoo-helper test -t --migration --dir .` - run migration test for all installable addons in current directory.
  This includes switching to stable branch, installing modules, optionally populating with extra data, switching back to test branch and running tests for migrated addons.
- `odoo-helper test --coverage-html <module>` - test single module and create html coverage report in current dir
- `odoo-helper test --coverage-html --dir .` - test all installable addons in current directory and create html coverage report in current dir

### Pre-commit

Odood use [pre-commit](https://pre-commit.com/) to run various linters, etc.
Thus following commands are used to deal with it:

- `odood pre-commit init` - Initialize pre-commit for repository. Create default pre-commit configurations.
- `odood pre-commit set-up` - Install pre-commit and all necessary dependencies in virtualenv.
- `odood pre-commit run` - Run pre-commit hooks for this repo manually.

### Repository management
- `odood repo add <url>` - fetch repository with third-party addons from git repo specified by `url`
- `odood repo add --oca <name>` - fetch OCA repository named `name` from OCA git repo. For example, `--oca web` means repo [web](https://github.com/OCA/web) from OCA.
- `odood repo add --github <username/repository>` - shortcut to easily fetch repo from github, by specifying only github username and repo name. For example: `--github oca/web` means repo [web](https://github.com/OCA/web) from OCA.
- `odood repo bump-versions` - increase versions of changed modules in git repo.

### Database management
- `odood db list` - list all databases available for current odoo instance
- `odood db create my_db` - create database
- `odood db backup -d my_db` - backup *my\_db*
- `odood db backup -a` - backup all databases on the server
- `odood db drop my_db` - drop database

### Translation management
- `odood tr regenerate --lang uk_UA <addon1> [addon2]...` - regenerate translations for specified language for specified addons
- `odood tr regenerate --lang uk_UA --addon-dir <path>` - regenerate translations for specified language for all installable addon in specified path

### Virtualenv management
- `odood venv run -- <command and args>` - Run some command inside virtualenv of this instance.
- `odood venv install-py-packages` - Install specified python packages in this virtualenv.
- `odood venv install-dev-tools` - Install development tools inside virtualenv of this instance.
- `odood ipython` - run ipython inside virtualenv of this instance.
- `odood venv reinstall` - resinstall virtual environment.
- `odood venv update-odoo` - update Odoo in this instance.
