# Introduction

![The Rust Logo](images/odood-logo.128.png)

## Overview

This project aims to simplify the process of development and maintenance
of addons developer for Odoo.

This project is successor of [odoo-helper-scripts](https://katyukha.gitlab.io/odoo-helper-scripts/)

Following features available:
- Super easy installation of Odoo for development
- Super easy installation of Odoo for production
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
- Support for assemblies: single repo with all addons for project, populated in semi-automatic way.
- Build with docker-support in mind

## Supported OS

Currently debian-based operation systems supported.
Tested on Ubuntu and Debian.


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

## Installation

To install Odood, just find debian package in [releases](https://github.com/katyukha/Odood/releases) and install it.
Thats all.

## Docker images

Odood has pre-build docker images with already installed Odoo and Odood.
These images could be useful as base to distribute products based on Odoo as docker images.
Take a look for base images at [github package registry](https://github.com/katyukha?tab=packages&repo_name=Odood).
