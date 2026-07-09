# Introduction

![The Odood Logo](images/odood-logo.128.png)

## Overview

This project aims to simplify following processes:
- development and maintenance of addons for Odoo
- deployment and maintenance of Odoo servers.

This project is successor of [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/)

Following features available:
- Super easy installation of Odoo for development
- Super easy installation of Odoo for production (see [docs](./production-deployment.md))
- Simple way to manage multiple development instances of Odoo on same developer's machine
- Everything (including [nodejs](https://nodejs.org/en/)) installed in [virtualenv](https://virtualenv.pypa.io/en/stable/) - no conflicts with system packages
- Best test runner for Odoo modules:
    - Easily run tests for developed modules
    - Show errors at the end of the log — a really useful feature for large (few megabytes) test logs
    - Test module migrations with ease
- Super easy installation of third-party addons:
    - Install modules directly from Odoo Apps
    - Easily connect git repositories with Odoo modules to Odoo instance managed by Odood
    - Automatic resolution of addons dependencies:
        - Handle `requirements.txt`
        - Handle [`odoo_requirements.txt`](https://katyukha.gitlab.io/odoo-helper-scripts/odoo-requirements-txt/)
- Simple database management via commandline: create, backup, drop, rename, copy database
- Simple installation via prebuilt debian package (see [releases](https://github.com/katyukha/Odood/releases))
- Support for [assemblies](./assembly.md): single repo with all addons for project, populated in semi-automatic way.
- Build with docker-support in mind
- Basic integration with [odoo-module-migrator](https://github.com/OCA/odoo-module-migrator). See [docs](./addon-migration.md)


## The War in Ukraine

2022-02-24 Russia invaded Ukraine...

If you want to help or support Ukraine to stand against the russian invasion,
please, visit [the official site of Ukraine](https://war.ukraine.ua/)
and find the best way to help.

Thanks.


## Supported OS

Currently *debian-based* operating systems are supported.
Tested on Ubuntu and Debian.
Theoretically it should work on macOS also.


## Supported Odoo versions

- Odoo 19.0 (experimental)
- Odoo 18.0 (tested)
- Odoo 17.0 (tested)
- Odoo 16.0 (tested)
- Odoo 15.0 (tested)
- Odoo 14.0 (tested)
- Odoo 13.0 (tested)
- Odoo 12.0 (tested)
- Odoo 11.0 (best efforts)
- Odoo 10.0 (best efforts)
- Odoo 9.0 (best efforts)
- Odoo 8.0 (best efforts)
- Odoo 7.0 (partial)


## Installation

Install the latest stable version on Debian/Ubuntu:

```bash
wget -O /tmp/odood.deb \
    "https://github.com/katyukha/Odood/releases/latest/download/odood_$(dpkg --print-architecture).deb"
sudo apt install -yq /tmp/odood.deb
```

On macOS (experimental), install via the Homebrew tap:

```bash
brew tap katyukha/odood
brew install odood
```

See [Installing Odood](./installation.md) for details: specific versions,
required system dependencies (postgresql, wkhtmltopdf), macOS notes, and
building from source.


## Docker images

Odood has pre-build docker images with already installed Odoo and Odood.
These images could be useful as base to distribute products based on Odoo as docker images.
Take a look for base images at [github package registry](https://github.com/katyukha?tab=packages&repo_name=Odood).

## License

Odood is distributed under MPL-2.0 license.
