# Assembly

Assembly is a reposityry that contains all third-party odoo addons needed for certain server,
that is populated with addons from various sources in semi-automatic way.

The main purpose of assembly is to simplify deployment process to production servers.

Assembly contains `odood-assembly.yml` file (that is also referenced as `assembly-spec`),
that describes list of addons and list of git sources to populate this assembly with.
All third-party addons will be placed into `dist` directory inside assembly during `sync` operation.

After `spec` is created/updated there is need to run `sync` operation as next step.
The `sync` operation updates assembly with latest versions of addons according to the `spec` definition.

So, after sync is completed, and changes pushed to assembly git repo,
the servers that use this assembly could be updated in single step, by calling command
`odood assembly upgrade` that will do all the job.


## Assembly Spec

Assembly spec is described in `odood-assembly.yml` file in root directory of assembly.

Assembly spec is [YAML](https://yaml.org/) file that looks like:

```yaml
spec:
  addons-list:
  - name: generic_m2o
  - name: generic_mixin
  - name: generic_tag
  sources-list:
  - url: https://github.com/crnd-inc/generic-addons
    ref: '17.0'
```

## Assembly workflow

Typical assembly workflow could be splitted on two parts:
- Assembly maintenance
- Server operations

The first one includes such operations like:
- Initialization of new assembly
- Management of assembly spec, that describes what addons and from what sources have to be included in assembly.
- Assembly synchronization - just pull latest versions of addons defined in spec, and update the assembly repo.

The second one, includes operations to be performed on server side.
These operations includes:
- Configure server to use assembly
- Upgrade server

At this moment, assembly spec have to be managed manually, by editing `odood-assembly.yml` file.
In future, some automation may be added.

What assembly created, and server is configured to use assembly,
the server management becomes pretty simple - all server updates could be done via single command:

```bash
odood assembly upgrade [--backup]
```

That will do all the job: pull assembly changes, relink modules, update addons on all databases, etc.


## Assembly management

There is group of commands designed to deal with assemblies: `odood assembly`.
Run `odood assembly --help` to get more info about available commands.

This group contains following commands:
- `odood assembly init` - allows to initalize assembly (new assembly or clone existing assembly from git)
- `odood assembly status` - show current status of assembly
- `odood assembly sync` - this command synchronizes assembly to actual state. This operation includes following steps done automatically:
  - Clone or update (pull) all git sources listed in spec
  - Remove all addons in `dist` folder of assembly
  - Copy latest versions of addons to `dist` folder
  - Add copied addons to git index of assembly repo
  - Optionally commit chages to assembly git repo
- `odood assembly link` - completely relink this assembly (remove all links to assembly from `custom_addons`, and create new links). This is needed to ensure that only actual assembly addons linked.
- `odood assembly pull` - pull changes for assembly repo. Useful during server update
- `odood assembly upgrade` - simple way to upgrade server that is configured to use assembly.
- `odood addons update --assembly` - this option could be used for `odood addons install/update/uninstall` commands to install/update/uninstall addons contained in assembly.

Also, command `odood addons find-installed` could be used to generate spec for assembly based on third-party addons installed in specified database(s).
This is useful to migrate already existing Odood project to use assembly instead of multiple repositories.
