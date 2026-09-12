# Assembly

Assembly is a repository that contains all third-party odoo addons needed for certain server,
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

  - generic_tag   # Addons could be specified by name only.
  sources-list:
  - github: crnd-inc/generic-addons  # converted to https://github.com/crnd-inc/generic-addons
  - oca: web  # converted to https://github.com/OCA/web
  - crnd: mygroup/my-repo  # converted to ssh://git@gitlab.crnd.pro/mygroup/my-repo
```

### SSH for local development

The `url:`, `github:`, and `oca:` shortcuts produce HTTPS URLs, which is the right default for
CI environments that use token-based authentication (see [Private git sources](#private-git-sources)).
If you prefer SSH on your developer machine — to use your SSH keys and avoid credential prompts —
configure git's built-in URL rewriting once in your global git config:

```bash
git config --global url."git@github.com:".insteadOf "https://github.com/"
git config --global url."git@gitlab.com:".insteadOf "https://gitlab.com/"
```

This transparently rewrites HTTPS URLs to SSH at the `git` level whenever Odood runs
`git clone` or `git fetch`. The `odood-assembly.yml` spec stays unchanged, so CI keeps working
with HTTPS while you get SSH locally.

### Source naming and addon binding

Sources can be given a `name`, which serves two purposes:
- it allows addons to be explicitly bound to a specific source via the `source` field
- it is used as the credential lookup key when the source is private (see [Private git sources](#private-git-sources))

```yaml
spec:
  addons-list:
  - name: my_addon
    source: my_repo      # fetch only from the source named "my_repo"
  - name: other_addon    # no binding — Odood searches all sources
  sources-list:
  - url: https://github.com/my/repo
    name: my_repo
    ref: 18.0
  - url: https://github.com/other/repo
    ref: 18.0
```

When `source` is set on an addon, Odood will only look for that addon in the named source.
This is useful when multiple sources contain a module with the same name.

### no-search flag

By default, Odood searches every source for each addon that has no explicit `source` binding.
Setting `no-search: true` on a source opts it out of that automatic search — the source is only
used when an addon explicitly references it by name.

```yaml
spec:
  addons-list:
  - name: my_addon
    source: private_repo   # will be fetched; explicit binding bypasses no-search
  - name: shared_addon     # will NOT be found in private_repo (no-search is set)
  sources-list:
  - url: https://github.com/public/repo
    ref: 18.0
  - url: https://github.com/my/private-repo
    name: private_repo
    ref: 18.0
    no-search: true
```

This is useful for large repositories where you want precise control over which addons are pulled,
or for private repositories that should only contribute explicitly listed addons.

### Commit pinning

Odood assemblies support commit pinning that could be used for supply-chain hardening.
A source can be pinned to a specific commit using the `commit` field in source definition.
`ref` is still required — it is used for an efficient single-branch clone, and `commit` is checked
out after the fetch.

```yaml
spec:
  addons-list:
    - name: my_addon
  sources-list:
    - url: https://github.com/my/repo
      ref: 18.0
      commit: a3f9c12bd047  # minimum 12 hex chars
```

Full 40-character SHAs are accepted as well as abbreviated hashes of at least 12 characters.
`commit` without `ref` is not allowed and will be rejected during spec validation.

### Odoo Apps addons

Additionally, it is allowed to download addons from [Odoo Apps](https://apps.odoo.com/apps).
For example, following spec, will download all addons from Odoo Apps. No git sources provided.

```yaml
spec:
  addons-list:
    - name: generic_m2o
      odoo_apps: true
    - name: generic_mixin
      odoo_apps: true
    - name: generic_tag
      odoo_apps: true
```

### Known addons

The `known-addons` list tells Odood about addons that are expected to be present on the target
server but are not managed by this assembly (e.g. modules that ship with Odoo itself, or modules
installed through a separate mechanism). These addons are excluded from dependency validation
during sync, so Odood will not report them as missing dependencies.

```yaml
spec:
  addons-list:
    - name: my_addon
  sources-list:
    - url: https://github.com/my/repo
      ref: 18.0
  known-addons:
    - sale
    - account
    - stock
```

### Assembly layout

The `layout` field controls where synced addons are placed inside the assembly repository.
Two values are supported:

- `standard` *(default)* — addons are placed in the `dist/` subdirectory.
- `flat` — addons are placed directly in the root of the assembly repository.

```yaml
spec:
  addons-list:
    - name: my_addon
  sources-list:
    - url: https://github.com/my/repo
      ref: 18.0
  layout: flat
```

The `flat` layout is useful when the assembly repository itself is used directly as an Odoo
addons path without a `dist/` indirection.

## Assembly workflow

Typical assembly workflow could be split into two parts:
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

Instead of editing `odood-assembly.yml` by hand, you can let Odood update the
spec for you:

```bash
# Add the source (one of --url / --github / --oca / --crnd), naming it so addons
# can bind to it:
odood assembly add-source --github my/repo --name my_repo --ref 18.0

# Add the addon, optionally binding it to that source:
odood assembly add-addon my_addon --source my_repo
```

This produces the same spec as the manual edit above. The commands are
idempotent: an addon or source that is already present is skipped with a warning
rather than failing (handy in scripts and CI). Binding an addon to an unknown
`--source` name is still an error. Both commands accept `--commit` /
`--commit-message` / `--push` / `--push-to` to commit and push the spec change in
one step.

For **free** addons distributed through [Odoo Apps](https://apps.odoo.com/apps),
use `--odoo-apps` instead of binding to a source (only free addons can be
downloaded automatically — paid addons require a purchase):

```bash
odood assembly add-addon free_addon --odoo-apps
```

> **Note:** Odood manages `odood-assembly.yml` as a generated file — `add-addon`,
> `add-source`, and `upgrade-sources` rewrite it in canonical form. URL
> shortcuts (`github:` / `oca:` / `crnd:`) are expanded to full `url:` values and
> YAML comments are not preserved.

As next step, we have to *sync* the assembly, to make Odood pull latest versions of selected modules from specified sources.
We can do it using following command:

```bash
odood assembly sync
```

After this command, specified addons will be located (updated) in the `dist` folder inside the assembly, ready to commit.
Also, we have to manually add `odood-assembly.yml` to the git index before committing, to make sure the spec is committed too.

Next, we push the assembly to some git repo, and then we can use it on servers.

### Upgrading pinned sources

By default the examples above use a branch name as the source `ref` (e.g. `ref: 18.0`).
`odood assembly sync` will always clone or pull from the tip of that branch.

An alternative is to pin each source to a specific **version tag**:

```yaml
spec:
  addons-list:
    - name: my_addon
  sources-list:
    - url: https://github.com/my/repo
      ref: 18.0.1.2.3   # pinned to a release tag
```

Pinning to a tag makes the assembly fully reproducible — every sync produces the same result — and enables supply-chain hardening with commit pinning. The trade-off is that you must explicitly advance the pin when a new release is available.

`odood assembly upgrade-sources` automates that step. It queries each source's remote for the newest version tag matching the project's Odoo series, updates the spec, and (optionally) commits and pushes:

```bash
# Preview what would change (no commit):
odood assembly upgrade-sources

# Update spec, commit and push:
odood assembly upgrade-sources --commit --push
```

Sources whose `ref` is a branch name (e.g. `18.0`) are silently skipped — they are already always-latest and need no upgrade step.

After running `upgrade-sources`, follow up with `odood assembly sync` to pull the new addon versions into the `dist/` directory.

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

#### Docker Compose deployments

When running Odoo in Docker Compose, the assembly is baked into the Docker image at build time
rather than cloned on the server. Updates therefore follow a different workflow: build a new image,
stop the running container, run addon updates, restart with the new image.

See [Docker Compose — Upgrading assembly-based deployments](./deployment-docker-compose.md#upgrading-assembly-based-deployments)
for the full workflow including backup, recovery steps, and the recommended Compose service layout.

## Assembly management

There is group of commands designed to deal with assemblies: `odood assembly`.
Run `odood assembly --help` to get more info about available commands.

This group contains following commands:
- `odood assembly init` - allows to initialize assembly (new assembly or clone existing assembly from git)
- `odood assembly use` - allows to configure server to use assembly from specified path. Useful in CI flows.
- `odood assembly status` - show current status of assembly
- `odood assembly sync` - this command synchronizes assembly to actual state. This operation includes following steps done automatically:
  - Clone or update (pull) all git sources listed in spec
  - Remove all addons in `dist` folder of assembly
  - Copy latest versions of addons to `dist` folder
  - Add copied addons to git index of assembly repo
  - Optionally commit changes to assembly git repo
- `odood assembly release` - assign the next assembly version, generate the release
  artifacts, commit them and create the release tag. See [Changelogs and versions](#changelogs-and-versions).
- `odood assembly link` - completely relink this assembly (remove all links to assembly from `custom_addons`, and create new links). This is needed to ensure that only actual assembly addons linked.
- `odood assembly pull` - pull changes for assembly repo. Useful during server update
- `odood assembly upgrade` - simple way to upgrade server that is configured to use assembly.
- `odood assembly upgrade-sources` - scan each source whose `ref` is a version tag and update the spec to the newest matching tag found on the remote. See [Upgrading pinned sources](#upgrading-pinned-sources).
- `odood addons update --assembly` - this option could be used for `odood addons install/update/uninstall` commands to install/update/uninstall addons contained in assembly.

Also, command `odood addons find-installed` could be used to generate spec for assembly based on third-party addons installed in specified database(s).
This is useful to migrate already existing Odood project to use assembly instead of multiple repositories.

## Private git sources

Assemblies can clone private git repositories via access tokens.
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
      commit: a3f9c12bd047   # optional: pin to a specific commit
      access-group: my_repos
```

Odood will check environment variable `ODOOD_ASSEMBLY_my_repos_CRED` for access credentials for this repo.
The format for this variable is: `user:token`

Note, that in case of [GitHub Actions](https://docs.github.com/en/actions), you have to provide access token for private repo in [GitHub Actions Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).
Thus, additionally in CI workflow definition, you have to assign secret to correct environment variable (see [docs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets#using-secrets-in-a-workflow)).

## Changelogs and versions

An assembly is versioned by git tags, and `odood assembly release` is what
assigns a version. `sync` only updates content — it never bumps a version,
because at sync time there is nothing to tag yet: on a PR-based flow the tag
cannot exist until the branch is merged, and two PRs branched from the same
point would otherwise both claim the same number.

A release assigns the version once and writes it into every artifact from that
single value, so the tag, the changelog and the Docker image label cannot
disagree.

```bash
odood assembly release --changelog --dockerfile --push
```

This creates a tag named after the new version, and generates in the root
directory of the repo:
- `CHANGELOG.md` - full changelog, with the new release section prepended.
- `CHANGELOG.latest.md` - changelog of the latest release only.
- `VERSION` - the assembly version, **if the file already exists** (see below).

**Note**, that recommended flow for update process is to create separate branch for each update, and apply each update with merge request.

### Version

The version of an assembly is its latest release tag, in the format
`<odoo major>.<odoo minor>.<major>.<minor>.<patch>` — for example `18.0.1.2.3`.
`odood assembly status` reports it.

Following rules are applied to generate new repo version:
- Odoo serie (`<odoo major>.<odoo minor>`) will be set to project's Odoo version
- If some addons were deleted, then **major** version part will be increased
- If new addon added to assembly, **minor** version part will be increased (an addition is not breaking)
- If some of assembly addons changed **major** part, then **major** version part of assembly will be increased.
- If some of assembly addons changed **minor** part, then **minor** version part will be increased
- All other cases will increase **patch** part of assembly version.

### The `VERSION` file

Tags are the source of truth, but an assembly is often consumed outside its git
repo — as an archive, or as a Docker image — where tags are not available.
For those cases Odood can also keep the version in a `VERSION` file at the root
of the assembly.

The file is an optional artifact, like `ADDONS.md`: **its presence is the
opt-in**. If the assembly has a `VERSION` file, every release updates it. If it
does not, none is created unless you pass `--version-file`. It is only ever
written, never read to decide a version, so it cannot drift from the tag.

Assemblies created before tag-based releases keep working with no migration
step: when there is no tag yet, the first release reads `VERSION` to know what
version to bump from, and tags from there.

### CHANGELOG.md

The changelog file contains information about each update of assembly, that includes:
- Update version
- Update date
- Addons added (name and version of each addon)
- Addons removed (name and version of each addon)
- Addons updated (name, old_version, new_version for each addon)
- Notable changes (if updated addon has list of notable changes for specific versions)

#### Sample changelog

Below is example of changelog generated by Odood during *assembly release* operation:

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

This feature expects that addon developers provide information about notable changes of addon in following way:
- addon must contain directory `changelog` that will store changelogs for this addon
- for each version of addon that has *notable changes*, file `changelog/changelog.X.Y.Z.md` have to be added (here `X` - major version of module, `Y` - minor version of module, `Z` - patch version of module; Odoo serie is not taken into account). This file should contain description of notable changes in MarkDown format.
- **note**, there is limitation for only `h6` headers in `changelog/changelog.X.Y.Z.md` files, because all headers larger than `h6` will be used in final assembly changelog.

For example (in context of example above (*Sample changelog*)), we have to add `changelog/changelog.1.3.0.md` file inside root directory of module `some_addon` with following content:

```md
- Some new useful feature added. Now users should be happy.
```

### CHANGELOG.latest.md

This file in same format as `CHANGELOG.md`, but contains only info from last update.

### Previewing changes before release

Two ways to see the pending changelog before any version is assigned:

- `odood assembly release --dry-run --changelog` prints the rendered changelog
  section to stdout, without writing, committing or tagging anything.
- `odood assembly sync --changelog-preview` writes the pending changes into
  `CHANGELOG.md` under an `## Unreleased` heading, so an update branch can
  carry the changelog in its diff (for example, for review in a merge
  request). Re-running the sync replaces the section with the current state;
  uncommitted hand edits to the changelog are refused, not overwritten.

No cleanup is needed for the `## Unreleased` section:
`odood assembly release --changelog` regenerates the changelog from the last
release, replacing it with the released section.


## Sample CI configuration to build/update assemblies automatically

Usually assemblies require CI to update modules automatically or semi-automatically.

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
      image: ghcr.io/katyukha/odood/odoo/18.0:latest
    steps:
      - uses: actions/checkout@v4
        with:
          # --changelog-preview measures changes since the last release tag.
          fetch-depth: 0

      - name: Add current directory as safe directory for git
        run: git config --global --add safe.directory "$(pwd)"

      - name: Sync assembly
        run: |
          odood --config-from-env -v -d assembly -p . sync \
            --dockerfile \
            --changelog-preview \
            --commit \
            --commit-user='Github Action' \
            --commit-email='github-action@odood.dev' \
            --push
```

The `--dockerfile` flag instructs Odood to generate (or regenerate) a `Dockerfile` in the assembly
repository root on every sync. This Dockerfile copies the synced `dist/` directory into the image
and runs `odood addons link` — it is what enables building a Docker image from the assembly.

The `--changelog-preview` flag writes the pending changelog under an
`## Unreleased` heading, so the update branch carries it in the pull-request
diff — see [Previewing changes before release](#previewing-changes-before-release).

Note that this workflow only syncs content — it does not assign a version.
Releasing is a separate step, see [Release the assembly on GitHub CI](#release-the-assembly-on-github-ci).

This workflow runs on all branches matching `18.0-*`. Usual flow:
1. Create a new branch `18.0-update`
2. Wait for the job to complete
3. Create a pull request
4. Review and merge the pull request
5. Delete the `18.0-update` branch (or configure automatic stale-branch deletion)

#### Semi-automatic update cycle (recommended)

The workflow above commits directly to the current branch.
For a more controlled flow that requires human review before merging, use a separate
workflow that creates a PR automatically:

```yaml
name: Init assembly sync
on: workflow_dispatch

jobs:
  init-assembly-sync:
    name: Init assembly sync
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    container:
      image: ghcr.io/katyukha/odood/odoo/18.0:latest
    env:
      # Credentials for private repos (if needed):
      # ODOOD_ASSEMBLY_myrepo_CRED: "x-access-token:${{ secrets.MY_REPO_PAT }}"
    steps:
      - uses: actions/checkout@v4

      - name: Add current directory as safe directory for git
        run: git config --global --add safe.directory "$(pwd)"

      - name: Use current repo as assembly
        run: odood -v -d --config-from-env assembly use .

      - name: Sync assembly
        run: |
          odood -v -d --config-from-env assembly sync \
            --commit \
            --commit-user='Github Action' \
            --commit-email='github-action@odood.dev' \
            --push-to=18.0-assembly-update \
            --fail-nothing-to-commit

  create-pull-request:
    name: Create assembly sync PR
    runs-on: ubuntu-latest
    needs: init-assembly-sync
    permissions:
      contents: read
      pull-requests: write
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - id: check-pr-exists
        run: |
          prs=$(gh pr list \
              --repo "$GITHUB_REPOSITORY" \
              --head '18.0-assembly-update' \
              --base '18.0' \
              --json title \
              --jq 'length')
          if ((prs > 0)); then
              echo "pr_exists=true" >> "$GITHUB_OUTPUT"
          fi
      - if: '!steps.check-pr-exists.outputs.pr_exists'
        run: |
          gh label create auto-update \
            --repo "$GITHUB_REPOSITORY" \
            --description "Automatic update" \
            --force
          gh pr create \
            --repo "$GITHUB_REPOSITORY" \
            --draft \
            --title="Automatic assembly update" \
            --body="Automatic assembly update" \
            -l auto-update \
            -B 18.0 -H 18.0-assembly-update
```

Key flags used in the sync step:
- `--push-to=18.0-assembly-update` — pushes to a dedicated update branch instead of the current one.
- `--fail-nothing-to-commit` — exits non-zero if no addons changed, preventing a no-op PR.
- `assembly use .` — registers the current directory as the assembly path, needed when the assembly
  repository and the Odood project share the same repo.

Triggering this workflow creates a draft PR from `18.0-assembly-update` into `18.0` (if one does
not already exist). Pushing to `18.0-assembly-update` also triggers the `Sync assembly` workflow
above (it matches `18.0-*`), which re-runs to regenerate the Dockerfile and the
changelog preview.

#### Private repo notes

In case when private repo have to be added to assembly, following additional steps have to be applied:
1. Specify credentials for private repo (usually system user + access token) in [GitHub Actions Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
2. On *Sync assembly* step, assign variable `ODOOD_ASSEMBLY_accessgroup_CRED` value in format `user:password` that is fetched from action's secrets, where `accessgroup` is value specified in `access-group` or `name` property of corresponding git source

All the rest will be handled by Odood.

For example, in case when private git source is hosted on github, the *Sync assembly* step may look like:

```yaml
      - name: Sync assembly
        env:
            ODOOD_ASSEMBLY_myrepo_CRED: "x-access-token:${{ secrets.GH_MY_REPO_PAT }}"
        run: |
          odood --config-from-env -v -d assembly -p . sync \
            --commit \
            --commit-user='Github Action' \
            --commit-email='github-action@odood.dev' \
            --push
```

It is expected, that assembly contains git-source named `myrepo` or that has `access-group` equal to `myrepo`.
Also, it is expected that access-token for this git repo added to [GitHub Actions Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) under name `GH_MY_REPO_PAT`

### Release the assembly on GitHub CI

Once a sync has been merged into the stable branch, a second workflow assigns
the version and creates the tag:

```yaml
name: Release assembly
on:
  push:
    branches:
      - '18.0'
  workflow_dispatch:

jobs:
  release-assembly:
    name: Release assembly
    runs-on: ubuntu-latest
    permissions:
      contents: write
    container:
      image: ghcr.io/katyukha/odood/odoo/18.0:latest
    steps:
      - uses: actions/checkout@v4
        with:
          # Version resolution needs the history back to the last release tag.
          fetch-depth: 0

      - name: Add current directory as safe directory for git
        run: git config --global --add safe.directory "$(pwd)"

      - name: Use current repo as assembly
        run: odood -v -d --config-from-env assembly use .

      - name: Release assembly
        run: |
          odood -v -d --config-from-env assembly release \
            --changelog \
            --dockerfile \
            --commit-user='Github Action' \
            --commit-email='github-action@odood.dev' \
            --push
```

`fetch-depth: 0` matters: a shallow clone does not reach the previous release
tag, so the set of changes to describe cannot be computed. On GitLab CI the
equivalent is `GIT_DEPTH: 0`. What is needed is the commit graph, not old file
contents — on large assemblies add `filter: blob:none` to the checkout to keep
the full history while historical file contents are downloaded only on demand
(on GitLab CI: `GIT_FETCH_EXTRA_FLAGS: --filter=blob:none`). The release
commit and the tag are pushed to the stable branch, so the job needs write
access to it.

The working tree has to be clean when the release runs — commit the sync first
(or run both steps in the same job) so the tag points at exactly the content the
version was computed from.

If nothing changed since the last release, the command reports that and exits
successfully; add `--fail-nothing-to-release` to make that an error instead.

#### Releasing a Docker image

Once `odood assembly release --push` has pushed a release tag, a second workflow
builds a multi-architecture Docker image from that tag and publishes it to GHCR:

```yaml
name: Build release image
on:
  push:
    tags:
      - '18.0.*'
  workflow_dispatch:

jobs:
  build-and-push-docker-image:
    env:
      REGISTRY: ghcr.io
      IMAGE_NAME: ${{ github.repository }}
    permissions:
      contents: read
      packages: write
      attestations: write
      id-token: write
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Log in to the Container registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags, labels) for Docker
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=tag
            type=match,pattern=(\d+\.\d+\.\d+\.\d+)\.\d+,group=1

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push Docker image
        id: push
        uses: docker/build-push-action@v6
        with:
          push: true
          platforms: linux/amd64,linux/arm64
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}

      - name: Generate artifact attestation
        uses: actions/attest-build-provenance@v1
        with:
          subject-name: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          subject-digest: ${{ steps.push.outputs.digest }}
          push-to-registry: true
```

The image is built from the tagged commit, which already contains everything the
release generated: the synced `dist/`, the changelog, and the Dockerfile whose
`org.opencontainers.image.version` label matches the tag.

The `metadata-action` step derives two image tags from the release tag
(e.g. `18.0.1.2.3`):
- **Full version** (`18.0.1.2.3`) — pinned; use this in `docker-compose.yml` for reproducibility and rollback.
- **Minor version** (`18.0.1.2`) — floating; always points to the latest patch of that minor version.

Multi-arch builds (`linux/amd64,linux/arm64`) require QEMU and Docker Buildx.
Remove the `platforms` line if you only need `amd64`.

**Note on triggering:** a tag pushed with the default `GITHUB_TOKEN` does not
trigger other workflows — GitHub suppresses events from that token to prevent
workflow loops. So after the "Release assembly" workflow pushes the tag, either
run this workflow manually (`workflow_dispatch`, choosing the release tag as the
ref), or make the release workflow check out with a personal access token, so
that its pushes do emit events:

```yaml
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.RELEASE_PAT }}
```

#### Full release cycle

```
1. Trigger "Init assembly sync" (workflow_dispatch)
      → syncs addons, commits, pushes to 18.0-assembly-update, opens draft PR
      → "Sync assembly" fires automatically on the new branch, regenerates
        the Dockerfile and the changelog preview
2. Review and merge the PR to 18.0
3. "Release assembly" fires on the push to 18.0
      → computes the next version from the changes since the last release tag,
        generates changelog / VERSION / Dockerfile, commits, tags and pushes
4. "Build release image" fires on the tag push (or is triggered manually — see
   the note on triggering above)
      → builds and pushes the multi-arch Docker image tagged with the version
5. Deploy using the upgrade workflow:
      → see Upgrading assembly-based deployments in Docker Compose docs
```

### Build assembly on GitLab CI

Sample GitLab CI configuration, that will build assembly automatically:

```yaml
build_assembly_on_commit:
    image: ghcr.io/katyukha/odood/odoo/18.0:latest
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
