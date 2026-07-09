# Assembly Spec Reference

The assembly spec is stored in `odood-assembly.yml` in the root of the assembly repository.
It is a [YAML](https://yaml.org/) file with a single required top-level key: `spec`.

```yaml
spec:
  addons-list: [...]
  sources-list: [...]
  known-addons: [...]
  layout: standard
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
| `ref` | no | `null` | Branch or tag to clone/fetch. Alias: `branch` (deprecated). |
| `commit` | no | `null` | Commit hash to check out after fetching `ref`. Minimum 12 hex characters. Requires `ref` to be set. |
| `access-group` | no | `null` | Credential group name for private repos. Overrides `name` for credential lookup. See [Private git sources](./assembly.md#private-git-sources). |
| `no-search` | no | `false` | When `true`, Odood will not auto-search this source for addons. The source is still used when an addon explicitly binds to it via `source:`. |

---

## Layout

| Value | Behaviour |
|-------|-----------|
| `standard` | Synced addons are placed in the `dist/` subdirectory of the assembly repo. |
| `flat` | Synced addons are placed directly in the root of the assembly repo. |

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
```
