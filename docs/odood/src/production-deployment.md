# Production deployment

## Overview

Production installation more focuses on security, and stabiltiy.
Thus, it do following additional tasks:
- Creates separate user to run Odoo
- Creates systemd service or init script to run Odoo at startup
- Optionally configures:
  - logrotate
  - nginx
  - fail2ban
  - certbot

Also, production installation expectes that it is running on clean system, and no other Odoo installed on same system.

## Indirect dependencies

**Note**, that *Odood* will not automatically install indirect dependencies, thus you have to manually install following system packages (if needed):
- [postgresql](https://www.postgresql.org/) - it is required to install postgresql server manually, before running `odood deploy` command if you use `--local-postgres` option.
- [wkhtmltopdf](https://github.com/wkhtmltopdf/packaging/releases) - Required to generate pdf reports. See [Odoo docs](https://github.com/odoo/odoo/wiki/Wkhtmltopdf) for more info.
- [nginx](https://nginx.org/) - if you want to exopose installed Odoo to external world via `nginx`. In this case, `Odood` will automatically generate template config for `nginx`.
- [certbot](https://certbot.eff.org/) - if you want to automatically generate [Let's Encrypt](https://letsencrypt.org/) certificates.
- [fail2ban](https://github.com/fail2ban/fail2ban) [Optional] - if you want to automatically block incorrect logins by IP. In this case Odood will automatically generate configs for `fail2ban`.

In case of Ubuntu:24.04 system required dependencies could be installed via command:

```bash
sudo apt install postgresql nginx certbot

wget -O /tmp/wkhtmltopdf-0.12.6.1-3.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install /tmp/wkhtmltopdf-0.12.6.1-3.deb
```

## Deployment

So, let's assume that all needed indirect system dependencises (in example it is only postgresql server) already installed.
Then, use following command to install Odoo 18 for production with local postgres:

```bash
sudo odood deploy -v 18 --local-postgres --supervisor=systemd
```

After this command completed, there will be installed Odoo and it will be configured to use local postgresql.
This Odoo instance will be managed by `systemd` service.

**Note:** on production installation each call to `odood` have to be run as `sudo` or from superuser.
Odood will automatically handle switching access rights when needed.

Also, it is recommended to use [assembly](./assembly.md) functionality to manage third-party addons on production instances.
This way, it is possible to deploy server in following way:

```bash
sudo odood deploy -v 18 \
    --local-postgres \
    --supervisor=systemd \
    --assembly-repo=htpps://github.com/my/assembly
```

This way, server will be automatically configured to use assembly `htpps://github.com/my/assembly`

## Complete sample: Pulic server

Following list of commands will install Odoo with configured nginx, postgresql, certbot and fail2ban on sever available in public space.

This sample, assumes, that you have control over your domain, and already point your domain to server where Odoo have to be installed.

**Note**, you have to update command below with your correct architecture.

So,
Let 's run following commands to get complete  production ready Odoo installation on Ubuntu 24.04 on amd64 architecture:

```bash
sudo apt-get update -yq    # update list of packages
sudo apt-get upgrade -yq   # upgrade packages

# Install required system dependencies
sudo apt-get install -yq wget nginx postgresql certbot fail2ban

# Download and install latest version of Odood
wget -O /tmp/odood.deb https://github.com/katyukha/Odood/releases/download/v0.5.1/odood_v0.5.1_amd64.deb
sudo apt install -yq /tmp/odood.deb

# Download and install correct version of Wkhtmltopdf
wget -O /tmp/wkhtmltopdf-0.12.6.1-3.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install -yq /tmp/wkhtmltopdf-0.12.6.1-3.deb

# Deploy Odoo 18.0 on the server
sudo odood deploy \
    -v 18 \
    --local-postgres \
    --supervisor=systemd \
    --enable-logrotate \
    --enable-fail2ban \
    --local-nginx-server-name=my.test.server \
    --letsencrypt-email=me@my.test.server
```

## Complete sample: Private network server with self-signec SSL certificates

Following list of commands will install Odoo with configured nginx, postgresql, on sever private network with self-signed SSL certificates under following paths:
- /etc/nginx/ssl/my.test.server.int.crt/etc/nginx/ssl/my.test.server.int.crt
- /etc/nginx/ssl/my.test.server.int.key

This sample, assumes, that you have already generate self-signed certificates.

**Note**, you have to update command below with your correct architecture.

So,
Let 's run following commands to get complete  production ready Odoo installation on Ubuntu 24.04 on amd64 architecture:

```bash
sudo apt-get update -yq    # update list of packages
sudo apt-get upgrade -yq   # upgrade packages

# Install required system dependencies
sudo apt-get install -yq wget nginx postgresql certbot fail2ban

# Download and install latest version of Odood
wget -O /tmp/odood.deb https://github.com/katyukha/Odood/releases/download/v0.5.1/odood_v0.5.1_amd64.deb
sudo apt install -yq /tmp/odood.deb

# Download and install correct version of Wkhtmltopdf
wget -O /tmp/wkhtmltopdf-0.12.6.1-3.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
sudo apt install -yq /tmp/wkhtmltopdf-0.12.6.1-3.deb

# Deploy Odoo 18.0 on the server
sudo odood deploy \
    -v 18 \
    --local-postgres \
    --supervisor=systemd \
    --enable-logrotate \
    --local-nginx-server-name=my.test.server.int \
    --local-nginx-ssl \
    --local-nginx-ssl-cert=/etc/nginx/ssl/my.test.server.int.crt \
    --local-nginx-ssl-key=/etc/nginx/ssl/my.test.server.int.key
```
