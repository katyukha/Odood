# Production deployment

Production installation more focuses on security, and stabiltiy.
Thus, it do following additional tasks:
- Creates separate user to run Odoo
- Creates systemd service or init script to run Odoo at startup
- Optionally configures:
  - logrotate
  - nginx
  - fail2ban

Also, production installation expectes that it is running on clean system, and no other Odoo installed on same system.

**Note**, that *Odood* will not automatically install indirect dependencies, thus you have to manually install following system packages (if needed):
- [postgresql](https://www.postgresql.org/) - it is required to install postgresql server manually, before running `odood deploy` command if you use `--local-postgres` option.
- [wkhtmltopdf](https://github.com/wkhtmltopdf/packaging/releases) - Required to generate pdf reports. See [Odoo docs](https://github.com/odoo/odoo/wiki/Wkhtmltopdf) for more info.
- [nginx](https://nginx.org/) - if you want to exopose installed Odoo to external world via `nginx`. In this case, `Odood` will automatically generate template config for `nginx`.
- [fail2ban](https://github.com/fail2ban/fail2ban) - if you want to automatically block incorrect logins by IP. In this case Odood will automatically generate configs for `fail2ban`.

So, let's assume that all needed indirect system dependencises (in example it is only postgresql server) already installed.
Then, use following command to install Odoo 18 for production with local postgres:

```bash
sudo odood deploy -v 18 --local-postgres --supervisor=systemd
```

After this command completed, there will be installed Odoo and it will be configured to use local postgresql.
This Odoo instance will be managed by `systemd` service.

**Note:** on production installation each call to `odood` have to be run as `sudo` or from superuser. Odood will automatically handle switching access rights when needed.

Also, it is recommended to use *assembly* functionality to manage third-party addons.
