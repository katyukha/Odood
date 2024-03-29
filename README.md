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
- [ ] Linters


## Installation (as Debian Package)

1. Download package for your os from [Releases](https://github.com/katyukha/Odood/releases)
2. Install downloaded debian package
3. Run `odood --help` to get info about available commands


## Installation (locally from source)

If you want to install it locally from source, follow steps below:

0. Clone this repository and checkout in the repository root.
1. Install system dependencies for this project (you can check lists of depenencies [here](https://github.com/katyukha/Odood/tree/main/.ci/deps)).
2. Install [DLang compiler](https://dlang.org/download.html)
3. Build Odood
    - Find the version of python you use (`python3 --version`)
    - Run command `dub build -b release --override-config=pyd/pythonXY` where `X` is major version of python and `Y` is minor version of python.
      For example, if you use Python 3.11, then command to build Odoo will look like `dub build -b release --override-config=pyd/python311`
    - After build completed, there will be generated binary `odood` in `build` directory.
4. Link Odoo binary to bin directory:
    - Assume that current working directory is Odood source code root.
    - `mkdir -p ~/bin`
    - `ln -s "$(pwd)/build/odood" ~/bin/`
5. Run `odood --help` to get info about available commands


## Use in parallel with [odoo-helper](https://katyukha.gitlab.io/odoo-helper-scripts/)

The only thing needed to manage [odoo-helper](https://katyukha.gitlab.io/odoo-helper-scripts/)
project with Odood is to run command `odood discover odoo-helper` somewhere inside
[odoo-helper](https://katyukha.gitlab.io/odoo-helper-scripts/) project.


## Level up your service quality

Level up your service quality with [Service Desk](https://crnd.pro/solutions/service-desk) / [ITSM](https://crnd.pro/itsm) solution by [CR&D](https://crnd.pro/).

Just test it at [yodoo.systems](https://yodoo.systems/saas/templates): choose template you like, and start working.


## License

Odood is distributed under MPL-2.0 license.
