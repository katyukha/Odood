# Odood

The easy way to install and manage odoo for local development.
This project is successor of [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/) and is compatible with
odoo installations made by [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/).

---

[![Github Actions](https://github.com/katyukha/odood/actions/workflows/tests.yml/badge.svg)](https://github.com/katyukha/odood/actions/workflows/tests.yml?branch=main)
[![codecov](https://codecov.io/gh/katyukha/odood/branch/main/graph/badge.svg?token=IUXBCNSHNQ)](https://codecov.io/gh/katyukha/odood)
[![DUB](https://img.shields.io/dub/v/odood)](https://code.dlang.org/packages/odood)
![DUB](https://img.shields.io/dub/l/odood)
![Current status](https://img.shields.io/badge/Current%20Status-Beta-purple)

---

## Overview

This project aims to simplify the process of development and maintenance
of addons developer for Odoo.

This project is successor of [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/)

Following features available:
- Super easy installation of Odoo for development
- Super easy installation of Odoo for production (see [docs](https://katyukha.github.io/Odood/production-deployment.html))
- Simple way to manage multiple development instances of Odoo on same developer's machine
- Everything (including [nodejs](https://nodejs.org/en/)) installed in [virtualenv](https://virtualenv.pypa.io/en/stable/) - no conflicts with system packages
- Best test runner for Odoo modules:
    - Easy run test for developed modules
    - Show errors in the end of the log, that is really useful feature for large (few megabytes size test logs)
    - Test module migrations with ease
- Super easy of third-party addons installation:
    - Install modules directly from Odoo Apps
    - Easily connect git repositories with Odoo modules to Odoo instance managed by Odood
    - Automatic resolution of addons dependencies:
        - Handle `requirements.txt`
        - Handle [`odoo_requirements.txt`](https://katyukha.gitlab.io/odoo-helper-scripts/odoo-requirements-txt/)
- Simple database management via commandline: create, backup, drop, rename, copy database
- Simple installation via prebuilt debian package (see [releases](https://github.com/katyukha/Odood/releases))
- Support for [assemblies](https://katyukha.github.io/Odood/assembly.html): single repo with all addons for project, populated in semi-automatic way.
- Build with docker-support in mind
- Basic integration with [odoo-module-migrator](https://github.com/OCA/odoo-module-migrator). See [docs](https://katyukha.github.io/Odood/addon-migration.html)


## The War in Ukraine

2022-02-24 Russia invaded Ukraine...

If you want to help or support Ukraine to stand against russian inavasion,
please, visit [the official site of Ukraine](https://war.ukraine.ua/)
and find the best way to help.

Thanks.


## Supported Odoo versions

- Odoo 7.0 (partial)
- Odoo 8.0 (best efforts)
- Odoo 9.0 (best efforts)
- Odoo 10.0 (best efforts)
- Odoo 11.0 (best efforts)
- Odoo 12.0 (tested)
- Odoo 13.0 (tested)
- Odoo 14.0 (tested)
- Odoo 15.0 (tested)
- Odoo 16.0 (tested)
- Odoo 17.0 (tested)
- Odoo 18.0 (tested)

## Prebuild docker-images with preinstalled Odoo and Odood

You can use on of [prebuilt images](https://github.com/katyukha?tab=packages&repo_name=Odood) to run Odoo managed by Odood in containers:
- [Odoo 18](https://ghcr.io/katyukha/odood/odoo/18.0)
- [Odoo 17](https://ghcr.io/katyukha/odood/odoo/17.0)
- [Odoo 16](https://ghcr.io/katyukha/odood/odoo/16.0)
- [Odoo 15](https://ghcr.io/katyukha/odood/odoo/15.0)


## Installation (as Debian Package)

To install Odood, just find debian package in [releases](https://github.com/katyukha/Odood/releases) and install it.
Thats all.

Note, that usually you will need to manually install additional system packages, that include:
- [postgresql](https://www.postgresql.org/) - if you plan to use local instance of postgresql.
- [wkhtmltopdf](https://github.com/wkhtmltopdf/packaging/releases) - Required to generate pdf reports. See [Odoo docs](https://github.com/odoo/odoo/wiki/Wkhtmltopdf) for more info.


## Installation (on MacOS)

There is experimental support for MacOS implemented as homebrew's [tap](https://github.com/katyukha/homebrew-odood).
Just run:

```bash
brew tap katyukha/odood
brew install odood
```

It is recommented to use [pyenv](https://github.com/pyenv/pyenv) on MacOS to init Odood projects.
For example, use option `--pyenv` when creating new odood project via `odood init`:

```bash
odood init -v 18 --pyenv
```

Also, take into account that you have to install missing dependencies on MacOS.
If you know how to make MacOS support better, just create issue or pull request with your ideas or patches.


## Build Odood from sources

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

It is possible to easily add repositories with third-party addons to odood projects.
To do this, following command could be used

```bash
odood repo add --help
```

For example, if you want to add [crnd-inc/generic-addons](https://github.com/crnd-inc/generic-addons)
you can run following command:

```bash
odood repo add --github crnd-inc/generic-addons
```

## Example setup for docker compose

Odood has prebuilt docker images, that could be used to easily run Odoo powered by Odoo inside docker-based infrastructure.

See examples directory for more details.

Example `docker-compose.yml`:

```yml
version: '3'

volumes:
    odood-example-db-data:
    odood-example-odoo-data:

services:
    odood-example-db:
        image: postgres:15
        container_name: odood-example-db
        environment:
            - POSTGRES_USER=odoo
            - POSTGRES_PASSWORD=odoo-db-pass

            # this is needed to avoid auto-creation of database by postgres itself
            # databases must be created by Odoo only
            - POSTGRES_DB=postgres
        volumes:
            - odood-example-db-data:/var/lib/postgresql/data
        restart: "no"

    odood-example-odoo:
        image: ghcr.io/katyukha/odood/odoo/17.0:latest
        container_name: odood-example-odoo
        depends_on:
            - odood-example-db
        environment:
            ODOOD_OPT_DB_HOST: odood-example-db
            ODOOD_OPT_DB_USER: odoo
            ODOOD_OPT_DB_PASSWORD: odoo-db-pass
            ODOOD_OPT_ADMIN_PASSWD: admin
            ODOOD_OPT_WORKERS: "1"
        ports:
            - "8069:8069"
        volumes:
            - odood-example-odoo-data:/opt/odoo/data
        restart: "no"
```


## Level up your service quality

Level up your service quality with [Service Desk](https://crnd.pro/solutions/service-desk) / [ITSM](https://crnd.pro/itsm) solution by [CR&D](https://crnd.pro/).

Just test it at [yodoo.systems](https://yodoo.systems/saas/templates): choose template you like, and start working.


## License

Odood is distributed under MPL-2.0 license.
