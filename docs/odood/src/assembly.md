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

### Assembly maintenance

To create assembly, we have to have some Odood instance (may be local development instance), that will be used to maintain assembly.
So, let's assume that we have some Odood instance for Odoo 17, and we need to configure it to use assembly. We can initialize assembly as follows:

```bash
odood assembly init
```

This way, odood will create empty assembly for that project.
The generated assembly config (`odood-assembly.yml`) could look like:

```yaml
spec:
  addons-list: []
  sources-list: []
```

If we want to add new module `my_addon` from `github.com/my/repo` to assembly, then we have to do add following changes in spec (`odood-assembly.yml`):
- Add name of addon in `addons-list` section of `spec`
- Add information about source to fetch this addons from in `sources-list` section of `spec`

So, in result, our spec could look like:

```yaml
spec:
  addons-list:
    - name: my_addon
  sources-list:
    - url: https://github.com/my/repo
      ref: 17.0url: https://github.com/my/repo
```

As next step, we have to *sync* the assembly, to make Odood pull latest versions of selected modules from specified sources.
We can do it using following command:

```bash
odood assembly sync
```

After this command, specified addons will be located (updated) in `dist` folder inside assembly, and ready to commit.
Also, we have to manually add `odood-assembly.yml` to git index before commit, to make sure spec is committed too.

So, next we have to push assembly to some git repo and then we could use it on servers.

### Server operations

#### Initialize server with assembly
At first, on the server we have to configure it in the way to use already existing assembly (from git repo).
To do this, we have to call command `odood assembly init` specifying git repository to initialize assembly from.
For example:

```bash
odood assembly init --repo <url of git repo with assembly>
```

As next step, it is good to link assembly, to ensure all addons from assembly is available on the server.
To do this, we can use following command

```bash
odood assembly link --ual
```

So, after this steps the server is configured to use assembly.

#### Update of server assembly

When server is configured to use assembly, then server management becomes pretty simple - all server updates could be done via single command:

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
