# Introduction

![The Rust Logo](images/odood-logo.128.png)

## Overview

This project aims to simplify the process of development and maintenance
of addons developer for Odoo.

This project is successor of [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/)

Following features available:
- Super easy installation of Odoo for development
- Super easy installation of Odoo for production (see [docs](./production-deployment.md))
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
- Support for [assemblies](./assembly.md): single repo with all addons for project, populated in semi-automatic way.
- Build with docker-support in mind


## The War in Ukraine

2022-02-24 Russia invaded Ukraine...

If you want to help or support Ukraine to stand against russian inavasion,
please, visit [the official site of Ukraine](https://war.ukraine.ua/)
and find the best way to help.

Thanks.


## Supported OS

Currently *debian-based* operation systems supported.
Tested on Ubuntu and Debian.
Theoretically if should work on MacOS also.


## Supported Odoo versions

- Odoo 18.0 (experimental)
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


## Docker images

Odood has pre-build docker images with already installed Odoo and Odood.
These images could be useful as base to distribute products based on Odoo as docker images.
Take a look for base images at [github package registry](https://github.com/katyukha?tab=packages&repo_name=Odood).

## License

Odood is distributed under MPL-2.0 license.
