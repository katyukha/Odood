# Assembly

Assembly is a reposityry that contains all third-party odoo addons needed for certain server,
that is populated with addons from various sources in semi-automatic way.

The main purpose of assembly is to simplify deployment process to production servers.

Assembly contains `odood-assembly.yml` file (that is also referenced as `assembly-spec`),
that describes list of addons and list of git sources to populate this assembly with.
All third-party addons will be placed into `dist` dir inside assembly during `sync` operation.

The `sync` operation updates assembly with latest versions of addons according to `spec` definition.

In Odood project, assembly is located in `assembly` directory inside project root.


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

Typical workflow of using assemblies is following:
1. Init new project (dev or prod) in standard way
2. Init assembly
3. Update assembly spec with list of desired addons and git sources
4. Sync assembly.
5. Install update modules from assembly.

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
- `odood addons update --assembly` - this option could be used for `odood addons install/update/uninstall` commands to install/update/uninstall addons contained in assembly.

Also, command `odood addons find-installed` could be used to generate spec for assembly based on third-party addons installed in specified database(s).
This is useful to migrate already existing Odood project to use assembly instead of multiple repositories.
