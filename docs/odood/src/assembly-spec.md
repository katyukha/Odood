# Assembly Spec Reference

The assembly spec is stored in `odood-assembly.yml` in the root of the assembly repository.
It is a [YAML](https://yaml.org/) file with these top-level keys:

| Key | Required | Description |
|-----|----------|-------------|
| `spec` | yes | What the assembly contains. See [`spec` fields](#spec-fields). |
| `system-packages` | no | What any host running the assembly needs: servers and Docker images. See [System packages](#system-packages). |
| `packaging` | no | What odood produces from the assembly. See [Packaging](#packaging). |

```yaml
spec:
  addons-list: [...]
  sources-list: [...]
  known-addons: [...]
  layout: standard
system-packages:
  deb: [...]
packaging:
  dockerfile:
    with-odoo-requirements: false
```

---

## `spec` fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `addons-list` | yes | — | List of addon entries to include in the assembly. |
| `sources-list` | no | `[]` | List of git source entries to fetch addons from. Alias: `git-sources`. |
| `known-addons` | no | `[]` | Addon names assumed to be present on the target server; excluded from dependency validation. |
| `layout` | no | `standard` | Controls where synced addons are placed. See [Layout](#layout). |

---

## Addon entry

Each entry in `addons-list` is either a plain string (addon name only) or a mapping:

```yaml
addons-list:
  - my_addon                  # string shorthand — name only
  - name: other_addon         # mapping form
    source: my_repo           # optional: bind to a named source
  - name: free_addon
    odoo_apps: true           # optional: download from Odoo Apps (free addons only)
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | yes | — | Technical name of the Odoo addon. |
| `source` | no | `null` | Name of the source entry to fetch this addon from. When set, Odood will only search the named source and will fetch the addon even if that source has `no-search: true`. |
| `odoo_apps` | no | `false` | When `true`, download this addon from [Odoo Apps](https://apps.odoo.com/apps) instead of a git source. Only **free** addons can be downloaded automatically; paid addons require a purchase. |

---

## Source entry

Each entry in `sources-list` defines a git repository to clone addons from.
Exactly one of `url`, `github`, `oca`, or `crnd` must be provided.

```yaml
sources-list:
  - url: https://github.com/my/repo
    name: my_repo
    ref: 18.0
    commit: a3f9c12bd047
    access-group: my_repos
    no-search: false
```

### URL shortcuts

| Field | Expands to |
|-------|-----------|
| `url: <full-url>` | used as-is |
| `github: owner/repo` | `https://github.com/owner/repo` |
| `oca: repo` | `https://github.com/OCA/repo` |
| `crnd: group/repo` | `ssh://git@gitlab.crnd.pro/group/repo` |

**Local SSH preference:** `github:` and `oca:` expand to HTTPS, which works for CI token auth.
Developers who prefer SSH can configure git's `url.insteadOf` globally — see
[SSH for local development](./assembly.md#ssh-for-local-development).

### Source fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `url` / `github` / `oca` / `crnd` | yes | — | Git repository URL (see shortcuts above). |
| `name` | no | `null` | Identifier for this source. Used to bind addons via `source:` and as the credential lookup key for private repos. |
| `ref` | no | project's Odoo serie branch (e.g. `18.0`) | Branch or tag to clone/fetch. Alias: `branch` (deprecated). |
| `commit` | no | `null` | Commit hash to check out after fetching `ref`. Minimum 12 hex characters. Requires `ref` to be set. |
| `access-group` | no | `null` | Credential group name for private repos, used when no credentials are set for `name`. See [Private git sources](./assembly.md#private-git-sources). |
| `no-search` | no | `false` | When `true`, Odood will not auto-search this source for addons. The source is still used when an addon explicitly binds to it via `source:`. |

---

## System packages

A top-level key, beside `spec`:

```yaml
spec:
  addons-list: [...]
system-packages:
  deb:
    - ghostscript
    - poppler-utils
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `deb` | no | `[]` | Debian package names, as `apt-get install` takes them. Versions cannot be pinned. |

`deb` is the only supported key; another one is warned about, and dropped
when odood saves the file. Each name must follow Debian's rule for
package names: lowercase letters, digits, `+`, `-` and `.`, at least two
characters, starting with a letter or digit. See
[System packages](./assembly.md#system-packages) for how they are installed.

---

## Packaging

A top-level key, beside `spec`. It holds what odood produces from the assembly;
for now, the options of the generated `Dockerfile`:

```yaml
spec:
  addons-list: [...]
packaging:
  dockerfile:
    with-odoo-requirements: true
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `dockerfile.with-odoo-requirements` | no | `false` | The generated `Dockerfile` runs `odood assembly link --with-odoo-requirements`. |

`packaging.dockerfile` holds options only: it does not make odood generate
the `Dockerfile`; `odood assembly sync --dockerfile` and
`odood assembly release --dockerfile` do.

With `with-odoo-requirements: true`, the image build installs the addons'
Python requirements together with Odoo's own `requirements.txt`, so pip keeps
the versions Odoo pins. An addon requirement that needs another version of one
of them fails the build with pip's `ResolutionImpossible`; pin a compatible
version in the assembly's `requirements.txt`. The setting applies after
`odood assembly sync --dockerfile` regenerates the `Dockerfile`. See
[Python requirements](./assembly.md#python-requirements).

---

## Layout

| Value | Behaviour |
|-------|-----------|
| `standard` | Synced addons are placed in the `dist/` subdirectory of the assembly repo. |
| `flat` | Synced addons are placed directly in the root of the assembly repo. |

---

## Validation

`odood assembly sync` refuses a spec where:

- an addon is listed twice, or two sources share a `name`;
- a source has `commit` without `ref`;
- an addon sets both `source` and `odoo_apps`;
- an addon's `source` names no source in `sources-list`.

An addon without `source` is taken from the first source in `sources-list` that
contains it, skipping sources with `no-search: true`.

Every command that loads `odood-assembly.yml` follows one rule: **an unknown
key is warned about, a known key with a bad value is refused.**

An unknown key does not stop the file from loading, so a file written by a
newer odood still loads on an older one. That holds at every level: the top
level, `spec`, its addon and source entries, `system-packages` and
`packaging`. Odood warns about it, naming it in full: `pakaging`,
`spec.addons-list[my_addon].freeze`, `spec.sources-list[oca_web].access_group`
(a source without a name is named by its URL), `packaging.dockerfile.generate`.
A misspelled key leaves its setting off: `with-odoo-requirement: true`, for
example, does not enable the option.

Odood drops unknown keys when it saves the file, for example after
`odood assembly add-addon` or `add-system-package`. Fix a misspelled key
before running a command that changes the file.

Refused, because the value of a known key is wrong:

- a `system-packages` that is not a mapping, or a `deb` name that is not a
  valid Debian package name;
- a `packaging` or `packaging.dockerfile` that is not a mapping, or a
  `with-odoo-requirements` that is not `true` or `false`;
- `system-packages` inside `spec`: it is a top-level key.

---

## Complete example

```yaml
spec:
  addons-list:
    - generic_mixin                       # shorthand
    - name: generic_tag
    - name: generic_m2o
      source: generic_addons              # explicit source binding
    - name: free_addon
      odoo_apps: true                     # from Odoo Apps (free addons only)
  sources-list:
    - github: crnd-inc/generic-addons
      name: generic_addons
      ref: '18.0'
      commit: a3f9c12bd047               # pinned commit
    - oca: web
      ref: '18.0'
    - github: my/private-repo
      name: private_repo
      ref: '18.0'
      access-group: my_creds
      no-search: true                     # only used for explicitly bound addons
  known-addons:
    - sale
    - account
  layout: standard
system-packages:
  deb:
    - poppler-utils                       # binaries the addons call
packaging:
  dockerfile:
    with-odoo-requirements: true          # image keeps Odoo's pinned versions
```
