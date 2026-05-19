# Frequently used commands

Short list of frequently used Odood commands.
Each command in this list supports `-h` or `--help` option, that will
print actual documentation on the command.
Thus, if you want to get most complete and actual documentation on particular command,
just call if with `-h` option.

### Server management
- `odood start` - start odoo server
- `odood restart` - restart odoo server
- `odood stop` - stop odoo server
- `odood log` - see odoo server logs
- `odood browse` - open running odoo installation in browser

### Addons management
- `odood addons list <path>` - list odoo addons in specified directory
- `odood addons update-list` - update list of available addons in all databases available for this server
- `odood addons install <addon1> [addonN]` - install specified odoo addons for all databases available for this server; use `--missing-only` to skip already-installed ones
- `odood addons update <addon1> [addonN]` - update specified odoo addons for all databases available for this server; use `--installed-only` to skip non-installed ones
- `odood addons uninstall <addon1> [addonN]` - uninstall specified odoo addons for all databases available for this server
- `odood addons update --dir <path>` - find all installable addons in specified directory and update them
- `odood addons install --dir <path>` - find all installable addons in specified directory and install them
- `odood addons link .` - link all addons in current directory.
- `odood addons add -h` - add third-party addons from [odoo-apps](https://apps.odoo.com/apps) (free only) or from [odoo-requirements.txt](./odoo-requirements-txt.md)

Both `install` and `update` support `--ignore-unfinished-updates` to proceed even if the database has pending addon state transitions.

### Tests
- `odood test -t <module>` - test single module on temporary database
- `odood test -t --dir .` - test all installable addons in current directory
- `odood test -t --migration --dir .` - run migration tests for all installable addons in current directory
- `odood test --coverage-html -t <module>` - test single module and create html coverage report
- `odood test --coverage-html --dir .` - test all installable addons and create html coverage report

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
- `odood repo release --initial` - create the first release tag (`<serie>.1.0.0`) for a repository with no prior tags.
- `odood repo release` - auto-detect changed addons since the last tag, verify versions are bumped, and create the next release tag.
- `odood repo release --changelog --push` - generate `CHANGELOG.md`, commit it, tag, and push branch + tag to origin.

### Database management
- `odood db list` - list all databases available for current odoo instance
- `odood db create my_db` - create database
- `odood db backup -d my_db` - backup *my\_db*
- `odood db backup -a` - backup all databases on the server
- `odood db drop my_db` - drop database
- `odood db restore my_db path/to/backup` - restore database from backup

### Translation management
- `odood tr regenerate --lang uk_UA <addon1> [addon2]...` - regenerate translations for specified language for specified addons
- `odood tr regenerate --lang uk_UA --addon-dir <path>` - regenerate translations for specified language for all installable addon in specified path

### Assembly management
- `odood assembly init` - initialize new empty assembly for this instance
- `odood assembly init --repo=git@github.com:my/assembly.git` - initialize this instance with assembly from specified repo
- `odood assembly upgrade` - pull latest changes from assembly and upgrade server
- `odood assembly sync` - synchronize assembly according to spec: fetch latest versions of modules from specified sources and update assembly repo
- `odood assembly upgrade-sources` - advance version-tag-pinned sources in the spec to the newest matching tags on their remotes; follow up with `assembly sync` to apply
- `odood assembly link` - relink all addons that are in assembly

### Virtualenv management
- `odood venv run -- <command and args>` - Run some command inside virtualenv of this instance.
- `odood venv install-py-packages` - Install specified python packages in this virtualenv.
- `odood venv install-dev-tools` - Install development tools inside virtualenv of this instance.
- `odood ipython` - run ipython inside virtualenv of this instance.
- `odood venv reinstall` - resinstall virtual environment.
- `odood venv update-odoo` - update Odoo in this instance.
