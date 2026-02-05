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
    ref: '18.0'
```

Following shortcuts available for sources, to make spec more readable:

```yaml
spec:
  addons-list:
  - name: generic_mixin
  sources-list:
  - github: crnd-inc/generic-addons  # converted to https://github.com/crnd-inc/generic-addons
  - oca: web  # converted to https://github.com/OCA/web
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
So, let's assume that we have some Odood instance for Odoo 18, and we need to configure it to use assembly. We can initialize assembly as follows:

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
      ref: 18.0
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

That will do all the job:
0. Optionally backup all databases
1. pull assembly changes,
2. relink modules,
3. update addons on all databases.


## Assembly management

There is group of commands designed to deal with assemblies: `odood assembly`.
Run `odood assembly --help` to get more info about available commands.

This group contains following commands:
- `odood assembly init` - allows to initalize assembly (new assembly or clone existing assembly from git)
- `odood assembly use` - allows to configure server to use assembly from specified path. Useful in CI flows.
- `odood assembly status` - show current status of assembly
- `odood assembly sync` - this command synchronizes assembly to actual state. This operation includes following steps done automatically:
  - Clone or update (pull) all git sources listed in spec
  - Remove all addons in `dist` folder of assembly
  - Copy latest versions of addons to `dist` folder
  - Add copied addons to git index of assembly repo
  - Optionally commit chages to assembly git repo
  - Optionally generate changelog for assembly
- `odood assembly link` - completely relink this assembly (remove all links to assembly from `custom_addons`, and create new links). This is needed to ensure that only actual assembly addons linked.
- `odood assembly pull` - pull changes for assembly repo. Useful during server update
- `odood assembly upgrade` - simple way to upgrade server that is configured to use assembly.
- `odood addons update --assembly` - this option could be used for `odood addons install/update/uninstall` commands to install/update/uninstall addons contained in assembly.

Also, command `odood addons find-installed` could be used to generate spec for assembly based on third-party addons installed in specified database(s).
This is useful to migrate already existing Odood project to use assembly instead of multiple repositories.

## Private git sources

Assemblies can clone private git repostitories via access tokens.
For each source in spec, it is possible to specify `name` or `access-group`,
that could be used to check environment variables for access credentials to clone specified sources.

For example, if following source defined:

```yaml
spec:
  addons-list:
    - name: my_addon
  sources-list:
    - github: my/private-repo
      ref: 18.0
      access-group: my_repos
```

Odood will check environment variable `ODOOD_ASSEMBLY_my_repos_CRED` for access credentials for this repo.
The format for this variable is: `user:token`

Note, that in case of [GitHub Actions](https://docs.github.com/en/actions), you have to provide access token for private repo in [GitHub Actions Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).
Thus, additionally in CI workflow definition, you have to assign secret to correct environment variable (see [docs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets#using-secrets-in-a-workflow)).

## Changelogs and versions

Assemblies support automatic generation of changelogs and update of repository version.
The `odood assembly sync` command has option `--changelog`, that enables automatic generation of changelogs for assembly repo.

When this option passed, then Odood will generate and maintain automatically following files in root directory of repo:
- `VERSION` - this file will contain assembly version in format `<odoo major>.<odoo minor>.<major>.<minor>.<patch>`.
- `CHANGELOG.md` - full changelog, that will be updated on each *sync* automatically.
- `CHANGELOG.latest.md` - changelog of lates update.

**Note**, that recommended flow for update process is to create separate branch for each update, and apply each update with merge request.

### Version

Example of `VERSION` file content:
`18.0.1.2.3`

This file is updated automatically on each sync (if `--changelog` option used).
Following rules are applied to generate new repo version:
- Odoo serie (`<odoo major>.<odoo minor>`) will be set to project's Odoo version
- If new addon added to assembly, **major** version part will be increased
- If some addons were deleted, then **major** version part will be increased
- If some of assembly addons changed **major** part, then **major** version part of assembly will be increased.
- If some of assembly addons changed **minor** part, then **minor** version part will be increased
- All othe cases will increase **patch** part of assembly version.

### CHANGELOG.md

The changelog file contains information about each update of assembly, that includes:
- Update version
- Update date
- Addons added (name and version of each addon)
- Addons removed (name and version of each addon)
- Addons updated (name, old_version, new_version for each addon)
- Notable changes (if updated addon has list of notable changes for specific versions)

#### Sample changelog

Below is example of changelog generated by Odood during *assembly sync* operation:

```md
# Changelog

## Release 18.0.2.0.0 (2025-Dec-23 19:18:33)

### Added addons

- `my_new_addon` (18.0.0.1.0)

### Removed addons

- `my_old_addon` (18.0.0.0.3)

### Updated addons

- `some_addon` (18.0.1.2.1 -> 18.0.1.3.0)

### Notable changes

#### Addon `some_addon`

##### Version 1.3.0
- Some new useful feature added. Now users should be happy.

## Release 18.0.1.0.1 (2025-Dec-20 12:11:38)

### Updated addons

- `some_addon` (18.0.1.2.0 -> 18.0.1.2.1)
```

#### Notable changes

The idea for this section is to provide list of changes that could be interesting for end users.
For example, it could contain information about some feature implemented or some breaking changes.

This feature expectes that addon developers provide information about notable changes of addon in following way:
- addon must contain directory `changelog` that will store changelogs for this addon
- for each version of addon that has *notable changes*, file `changelog/changelog.X.Y.Z.md` have to be added (here `X` - major version of module, `Y` - minor version of module, `Z` - patch version of module; Odoo serie is not taken into account). This file should contain description of notable changes in MarkDown format.
- **note**, there is limitation for only `h6` headers in `changelog/changelog.X.Y.Z.md` files, becouse all headers larger than `h6` will be used in final assembly changelog.

For example (in context of example above (*Sample changelog*)), we have to add `changelog/changelog.1.3.0.md` file inside root directory of module `some_addon` with following content:

```md
- Some new useful feature added. Now users should be happy.
```

### CHANGELOG.latest.md

This file in same format as `CHANGELOG.md`, but contains only info from last update.


## Sample CI configuration to build/update assemblies automatically

Usually assembiles require CI to update modules automatically or semi-automatically.

### Build assembly on GitHub CI

Sample GitHub Actions workflow configuration, that will build assembly automatically:

```yaml
name: Sync assembly
on:
  push:
    branches:
      - '18.0-*'
  workflow_dispatch:

jobs:
  sync-assembly:
    name: Sync assembly
    if: "!contains(github.event.head_commit.message, '[SYNC] Assembly synced')"
    runs-on: ubuntu-latest
    strategy:
      fail-fast: true
    permissions:
      contents: write
      pull-requests: write
    container:
      image: ghcr.io/katyukha/odood/odoo/18.0:0.5.3
    steps:
      - uses: actions/checkout@v4

      - name: Add current directory as safe directory for git
        run: git config --global --add safe.directory "$(pwd)"

      - name: Sync assembly
        run: |
          odood --config-from-env -v -d assembly -p . sync \
            --changelog \
            --commit \
            --commit-user='Github Action' \
            --commit-email='github-action@odood.dev' \
            --push
```

This will run assembly build job for all branches starting from `18.0-` prefix.
Thus, usual flow looks like:
1. create new branch `18.0-update`
2. wait while job started
3. When job completed, create pull request
4. Review and merge pull request
5. Delete `18.0-update` branch (or configure to delete stale head branches automatically)

#### Private repo notes

In case when private repo have to be added to assembly, following additional steps have to be applied:
1. Specify credentials for private repo (usually system user + access token) in [GitHub Actions Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
2. On *Sync assembly* step, assign variable `ODOOD_ASSEMBLY_accessgroup_CRED` value in format `user:password` that is fetched from action's secrets, where `accessgroup` is value specified in `access-group` or `name` property of corresponding git source

All the rest will be handled by Odood.

For example, in case when private git source is hosted on github, the *Sync assembly* step may look like:

```yaml
      - name: Sync assembly
        env:
            ODOOD_ASSEMBLY_myrepo_CRED: "x-access-token:${{ secrets.GH_MY_REPO_PAT }}
        run: |
          odood --config-from-env -v -d assembly -p . sync \
            --changelog \
            --commit \
            --commit-user='Github Action' \
            --commit-email='github-action@odood.dev' \
            --push
```

It is expected, that assembly contains git-source named `myrepo` or that has `access-group` equal to `myrepo`.
Also, it is expected that access-token for this git repo added to [GitHub Actions Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) under name `GH_MY_REPO_PAT`

### Build assembly on GitLab CI

Sample GitLab CI configuration, that will build assembly automatically:

```yaml
build_assembly_on_commit:
    image: ghcr.io/katyukha/odood/odoo/18.0:0.5.3
    before_script:
        # Add current directory as safe, thus allowing git operations in this dir.
        - git config --global --add safe.directory "$(pwd)"

    script:
        # Create temporary branch to allow push work from Odood
        - git checkout -b 18.0-tmp-assembly
        # Do assembly sync
        - odood --config-from-env assembly -p . sync --commit --commit-user="GitLab Bot" --commit-email="gitlab-bot@odood.dev" --push --push-to "$CI_COMMIT_BRANCH"

    except:
        variables:
            # Do not run package on commits created by packager itself
            - $CI_COMMIT_MESSAGE =~ /\[SYNC\] Assembly synced/
        refs:
            # Do not run job for stable branches
            - "18.0"
    only:
        refs:
            - branches
```

Note, that it is required to allow gitlab-ci-token to push changes back to project.
This have to be configured in repository settings (CI/CD Settings -> Job token permissions)

Usually, it is required to create new branch to run build job.
