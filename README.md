# Odood

The easy way to install and manage odoo for local development.
This project is successor of [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/) and is compatible with
odoo installations made by [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/).

---

[![Github Actions](https://github.com/katyukha/odood/actions/workflows/tests.yml/badge.svg)](https://github.com/katyukha/odood/actions/workflows/tests.yml?branch=master)
[![codecov](https://codecov.io/gh/katyukha/odood/branch/master/graph/badge.svg?token=IUXBCNSHNQ)](https://codecov.io/gh/katyukha/odood)
[![DUB](https://img.shields.io/dub/v/odood)](https://code.dlang.org/packages/odood)
![DUB](https://img.shields.io/dub/l/odood)

---


## Current state

![Current status](https://img.shields.io/badge/Current%20Status-Alpha-purple)

The project is still *under development*.

Currently, this project could be used in parallel with [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/).

Following features currently implemented:
- [x] Server management
- [x] Database management
- [x] Basic addons management (fetch/install/update/uninstall)
- [x] Running tests
- [ ] CI utils (versions, forwardports, etc)
- [ ] Postgres utils
- [ ] Doc utils
- [x] Linters - use pre-commit and per-repo configurations, instead of directly running linters


## Installation (as Debian Package)

This is the recommended way to install Odood.

1. Download package for your os from [Releases](https://github.com/katyukha/Odood/releases)
2. Install downloaded debian package
3. Run `odood --help` to get info about available commands


## Installation (locally from source)

*Note*, that this way is mostly useful for development of Odood, and requires
significant RAM amount to build Odood. Better, download and install it as debian package.

If you want to install it locally from source, follow steps below:

0. Clone this repository and checkout in the repository root.
1. Install system dependencies for this project (you can check lists of depenencies [here](https://github.com/katyukha/Odood/tree/main/.ci/deps)).
2. Install [DLang compiler](https://dlang.org/download.html)
3. Build Odood with command `dub build -b release`. After build completed, there will be generated binary `odood` in `build` directory.
4. Link Odoo binary to bin directory:
    - Assume that current working directory is Odood source code root.
    - `mkdir -p ~/bin`
    - `ln -s "$(pwd)/build/odood" ~/bin/`
5. Run `odood --help` to get info about available commands


## Use in parallel with [odoo-helper](https://katyukha.gitlab.io/odoo-helper-scripts/)

The only thing needed to manage [odoo-helper](https://katyukha.gitlab.io/odoo-helper-scripts/)
project with Odood is to run command `odood discover odoo-helper` somewhere inside
[odoo-helper](https://katyukha.gitlab.io/odoo-helper-scripts/) project.


## Quick start

Use following command to create new local (development) odoo instance:

```bash
odood init -v 17 -i odoo-17.0 --db-user=odoo17 --db-password=odoo --http-port=17069 --create-db-user
```

This command will create new virtual environment for Odoo and install odoo there.
Also, this command will automatically create database user for this Odoo instance.

For production installations, you can use command `odood deploy` that will
deploy Odoo of specified version to machine where this command is running.
For example: `odood deploy -v 17 --supervisor=systemd --local-postgres --enable-logrotate`
But this command is still experimental.

Next, change current working directory to directory where we installed Odoo:

```bash
cd odoo-17.0
```

After this, just run command:

```bash
odood browse
```

and it will automatically start Odoo and open it in browser.

Next, you can use following commands to manage server:

```bash
odood server start
odood server stop
odood server restart
odood server log
```

Next, let's create some test database with pre-installed CRM module
for this instance:

```bash
odood db create --demo my-test-database --install=crm
```

After this command, you will have created odoo database `my-test-database` with
already installed module `crm`.

Additionally you can manage odoo addons from commandline via command `odood addons`.
See help for this command for more info:

```bash
odood addons --help
```

## Level up your service quality

Level up your service quality with [Service Desk](https://crnd.pro/solutions/service-desk) / [ITSM](https://crnd.pro/itsm) solution by [CR&D](https://crnd.pro/).

Just test it at [yodoo.systems](https://yodoo.systems/saas/templates): choose template you like, and start working.


## License

Odood is distributed under MPL-2.0 license.
