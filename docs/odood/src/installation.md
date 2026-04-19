# Installation

## Debian / Ubuntu

Download and install the latest stable release:

```bash
wget -O /tmp/odood.deb \
    "https://github.com/katyukha/Odood/releases/latest/download/odood_$(dpkg --print-architecture).deb"
sudo apt install -yq /tmp/odood.deb
```

To install a specific version, visit the [releases](https://github.com/katyukha/Odood/releases) page, download the `.deb` for the desired version and architecture, and install it the same way.

## macOS

macOS support is experimental. Install via the [Homebrew tap](https://github.com/katyukha/homebrew-odood):

```bash
brew tap katyukha/odood
brew install odood
```

On macOS, use [pyenv](https://github.com/pyenv/pyenv) to manage the Python version for Odood projects.
Pass `--pyenv` when creating a new project so Odood installs and configures the right Python version automatically:

```bash
odood init -v 18 --pyenv
```

Missing system dependencies (PostgreSQL client libraries, etc.) need to be installed manually.
If you run into issues or have improvements for macOS support, please open an issue or pull request.

## System dependencies

Odood itself is a self-contained binary, but the Odoo instances it manages need several system packages:

- **PostgreSQL** — required if you plan to run a local database server (`sudo apt install postgresql`).
- **wkhtmltopdf** — required to generate PDF reports. Download the right release for your OS from the [wkhtmltopdf releases](https://github.com/wkhtmltopdf/packaging/releases) page. See also the [Odoo docs on wkhtmltopdf](https://github.com/odoo/odoo/wiki/Wkhtmltopdf).

## Docker images

Prebuilt Docker images with Odoo and Odood already installed are published to the GitHub Container Registry:

```
ghcr.io/katyukha/odood/odoo/{serie}:latest
```

Available series: `16.0`, `17.0`, `18.0`, `19.0`.

These images are useful as a base for distributing Odoo-based products as containers, and for CI pipelines.
See [Docker Compose](./deployment-docker-compose.md) for deployment details.
