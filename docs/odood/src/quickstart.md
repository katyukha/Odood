# Quick start

## Overview

Odood is Command Line Interface (CLI) tool.
Odood and each subcommand of Odood has option `--help`, thus
if you are interested what it can do, just type `odood --help` :)

## Odoo installation

There are two types of Odoo installation supported by Odood:
- Development
- Production

### Development installation

Development installation is designed to be super easy for developer.
Thus it just installs Odoo and everything needed into specified directory.
No specific user for Odoo process, no access restrictions, etc.
Instead, it is designed to be able to work with multiple Odoo instances
installed on same system.

To install Odoo 17 for development, following command could be used:

```bash
odood init -i odoo-17 -v 18
```

But, usually it is used with other options, to use separate database user and separate port for each development Odoo instance.
For example:

```bash
odood init -i odoo-17 -v 18 --db-user=odoo18 --http-port=18069
```

After this command, Odoo 17 will be installed in `odoo-18` directory.
Next, if current working directory is inside `odoo-17`, then `odood` command could be used to manage this instance.


### Production installation

Production installation more focuses on security, and stabiltiy.
Thus, it do following additional tasks:
- Creates separate user to run Odoo
- Creates systemd service or init script to run Odoo at startup
- Optinally configures logrotate

Also, production installation expectes that it is running on clean system, and no other Odoo installed on same system.

To install Odoo 17 for production with local postgres, use following command on clean machine (with just Odood and [postgres](https://www.postgresql.org/) installed).

```bash
sudo odood deploy -v 17 --local-postgres --supervisor=systemd
```

After this command completed, there will be installed Odoo and it will be configured to use local postgresql.
This Odoo instance will be managed by systemd service.

**Note:** on production installation each call to `odood` have to be run as `sudo` or from superuser. Odood will automatically handle switching access rights when needed.

## Server management

After installation following commands available to manage Odoo server:
- `odood server start` - start Odoo in background
- `odood server stop` - stop Odoo if running 
- `odood server restart` - restart Odoo
- `odood server browse` - open Odoo in your browser
- `odood server run` - run odoo itself.
- `odood server log` - view server logs (automatically use `less` utility to view Odoo server log)
- `odood server status` - Check if Odoo server is running or not
- `odood status` - status of this Odoo instance.

## Database management

Now we can create new Odoo database inside installed Odoo instance.

To do this we can use following command:

```bash
odood db create --demo --tdb --recreate
```

This command will create new test Odoo database on this Odoo instance.
The name for test odoo database is generated automatically as `<dbuser>-odood-test`.
Such test database is useful during development stage: you do not need to thing about name of database
during frequent database creation/recreation.

Or, we can create demo database with specific name

```bash
odood db create --demo --recreate my-demo-db
```

Next we can view list of databases:

```bash
odood db list
```

Also, there is shortcut for this frequently used command:

```bash
odood lsd
```

Additionally following commands may be useful:
- `odood db drop`
- `odood db copy`
- `odood db backup`
- `odood db restore`
- `odood db rename`
- `odood db stun` - disable cron jobs and mail servers
- `odood db list-installed-addons` - show list of addons installed in specific DB

## Addons management

One of the frequent usecases of Odood is management of third-party modules (or own addons).

### Install third-party addon
Let's install for example module `generic_location` from [generic-addons](https://github.com/crnd-inc/generic-addons) repository.

To do this, we can use following command:

```bash
odood repo add https://github.com/crnd-inc/generic-addons
```

Or we can use shortcut:

```bash
odood repo add --github crnd-inc/generic-addons
```

This command will fetch specified git repository, and store it at `repositories/crnd-inc/generic-addons` directory in project root,
and all addons in that repo will be automatically symlinked to `custom_addons` directory inside project root,
thus they will become visible for Odoo.

Next, we could use following command to install module `generic_location` into created database:

```bash
odood addons install -d my-demo-db generic_location
```

After this command, module `generic_location` will be installed in database `my-demo-db`

### Update third-party modules

One of the most frequent tasks related to management of Odoo servers is update of third party modules.
In our case, we have repository `generic-addons`, and we may need to update modules from this repo.
To do this, we have to use following algorithm:
0. Take backup
1. Pull changes from repo (use `git pull` for this)
2. Stop Odoo server
3. Install / update all required dependencies
4. Run update for all modules from this repo for all databases.
5. Start Odoo server again

Using Odood for our example, it could be done in following way:

```bash
#  Change current working directory to repository that we want to update
cd repositories/crnd-inc/generic-addons

# Pull changes for the repository
git pull

# We have to relink addons in case when new addons were added
# or new python dependencies were added.
# With this command Odood will handle most of this cases automatically
odood addons link .

# Update all modules inside current directory for all databases
# Also, automatically update list of addons in each database.
# This command will automatically stop Odoo before update if needed
# and start again after update.
odood addons update -a --ual --dir .
```

### Addons management commands

- add - Add addons to the project
- update-list -Update list of addons.
- link - Link addons in specified directory.
- generate-py-requirements  - Generate python's requirements.txt from addon's manifests. By default, it prints requirements to stdout.
- update - Update specified addons.
- install - Install specified addons.
- is-installed - Print list of databases wehre specified addon is installed.
- uninstall - Uninstall specified addons.
- list - List addons in specified directory.

## Running tests

During development, it is frequent case to run automated tests for modules being developed.
So, Odood provides separate command `odood test` that runs tests for specified modules.

It is recommended to look at `--help` for this command (`odood test -h`) to get more info about what it can do.

In our case, let's run tests for module `generic_location`. to do this, we can run following command:

```bash
odood test -t generic_location
```

This command will create temporary database to run tests in, automatically find module `generic_location` and run tests for it with colored highlights for errors and warnings.

Also, it is possible to run test for whole repo.
Assume, we are inside `repositories/crnd-inc/generic-addons`, then we can just run command:

```bash
odood test -t --dir .
```

It will automatically find all addons in this repo, and run tests for all of them on same temporary database.

## Virtualenv managment

Additionally, sometimes it is useful to manage virtualenv of Odood project.
For this reason, Odood has `ododo venv` subcommand, that contains various commands to manage virtual environment of this project:

- install-dev-tools - Install Dev Tools
- run - Run command in this virtual environment. The command and all arguments must be specified after '--'. For example: 'odood venv run -- ipython'
- reinstall-odoo - Reinstall Odoo to different Odoo version.
- npm - Run npm for this environment. All arguments after '--' will be forwarded directly to npm.
- ipython - Run ipython in this environment. All arguments after '--' will be forwarded directly to python.
- python - Run python for this environment. All arguments after '--' will be forwarded directly to python.
- update-odoo - Update Odoo itself.
- pip - Run pip for this environment. All arguments after '--' will be forwarded directly to pip.
- reinstall - Reinstall virtualenv.
- install-py-packages - Install Python packages

