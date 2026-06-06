# Release Management

This page describes the release strategy for addon repositories managed with Odood,
covering version conventions, the standard release flow, and the hotfix flow.

> **Scope:** This page applies to *addon repositories* — git repositories containing
> one or more Odoo addons, with one stable branch per supported Odoo series.
> It is not about upgrading Odoo itself (see [Upgrading Odoo](./upgrading.md)).

---

## Why repository versions?

When multiple addon repositories depend on each other, there is a natural consistency
risk: repo A merges a breaking change, and repo B — which depends on A — has not yet
been updated. If assembly sources point to branches, any deploy during that window
picks up an inconsistent combination.

Repository versions solve this by giving each repo a pinnable snapshot. An assembly
spec can reference a specific release of repo A alongside a specific release of repo B —
a combination that was tested together. The typical promotion path then becomes:

1. Cut new releases of the relevant repos.
2. Update the assembly spec to pin the new versions.
3. Sync the assembly and deploy to a staging environment.
4. Validate. Promote to production.

Enabling this pinning is the *primary* reason repository versions exist — a
release is first and foremost an immutable, tested snapshot you can reference.
On top of that, the version *number* itself carries meaning: it follows
[semver](https://semver.org/)-like semantics derived from the aggregate addon
changes (see [Concepts](#concepts)), so the segment that changed signals whether
an upgrade may carry breaking changes.

### Code freeze, scoped to a tag

The traditional model — where the stable branch (e.g. `18.0`) is always deployable
and every merged PR is production-ready — works well for mature, slow-moving
repositories. For repositories under active development it creates a subtle risk:
the version deployed to a test environment and the version promoted to production
a day or two later may differ, because new commits landed on the branch in between.

The usual remedy is a **code freeze** — a window during which no new merges are
allowed while testing and promotion happen. That stabilises what you test, but at
the cost of blocking everyone's work for the duration.

Repository releases don't eliminate the freeze — they make it light, and they end
it with a tag. The *purpose* of a freeze is to have one immutable, tested thing to
promote, and a tag is exactly that: an immutable snapshot of a single commit. In
practice the cycle becomes:

1. **Active development** — feature branches merge into stable as usual.
2. **Light freeze** — in the run-up to a release, stop merging *new features* into
   stable. Bug fixes and translation updates are still welcome — that is the only
   restriction, so it is far less disruptive than a full merge freeze.
3. **Release** — when stable is in good shape, cut a tag. You test and promote that
   exact tag, so it no longer matters what lands on the branch afterwards.
4. **Next iteration** — held-back feature branches merge and active development
   resumes.

The freeze still exists, but it shrinks to "no new features for a short while,"
scoped to the snapshot the tag captures rather than to the branch as a whole.

### Translation batching

With branch-based pinning, translation updates must be kept in sync with ongoing
development and merged as they are ready. With release pinning, translations can be
batched and merged as a single MR in the days before a planned release, keeping
them entirely out of the development cycle until they are needed.

---

## Concepts

### Repository version

A repository version is a **git tag** on the stable branch. The git tag is the sole
source of truth. Tags follow the format `A.B.X.Y.Z`:

| Segment | Meaning |
|---------|---------|
| `A.B` | Odoo series (e.g. `18.0`) |
| `X` | Major — a breaking change: any addon had a **major** version bump, or an addon was **removed**, since the last release |
| `Y` | Minor — any addon had a **minor** or **patch** bump, or an addon was **added**, since the last release |
| `Z` | Patch — **only ever set by a deliberate patch release** (`release --patch` or `hotfix release`), never by auto-detection |

Repository versions follow [semver](https://semver.org/)-like semantics over the
aggregate of addon changes, so that — when addon authors follow the same
convention — a glance at the version segment that changed tells you whether a
release carries potentially breaking changes.

**Auto-detected releases always end in `.0`** (e.g. `18.0.1.0.0`, `18.0.2.1.0`).
A `Z > 0` tag is a **patch release**, produced only by a deliberate patch: either
`release --patch` (a mainline patch on the latest serie release) or the
[hotfix flow](#hotfix-flow) (`hotfix release`, on an older chain).

The bump level is computed automatically by `odood repo release` from the aggregate
of addon version changes since the last release tag. You can override it with
`--major`, `--minor`, or `--patch`.

> **Why does a patch-only addon change bump repository `Y`, not `Z`?**
> Because auto-detection never produces a `Z` bump — a routine release, even one
> that only contains addon patch bumps, always ends in `.0`. A `Z > 0` release
> requires a deliberate patch — `release --patch` (mainline) or the
> [hotfix flow](#hotfix-flow) (`hotfix release`, on an older
> chain).

### Addon versions

Addon versions (the `A.B.X.Y.Z` string in each addon's `__manifest__.py`) are a
**separate concern**, managed by each addon's maintainer independently of the
repository release cycle. The rule is: every change to an addon must increase its
version before the branch is merged to stable. This is enforced by CI on every pull
request — by the time anything lands on the stable branch, addon versions are already
correct.

`odood repo release` re-verifies this internally as a safety gate, but in normal
practice the gate is always clear by release time.

Addon version bump semantics (when to bump `X` vs `Y` vs `Z` within an addon) are
a separate topic and are not covered here.

---

## Standard Release Flow

Development follows a standard feature-branch model (see
[Development Workflow](./development-workflow.md) for branching strategy, local
testing, and CI/CD setup):

- Work happens on branches named after the target series (e.g. `18.0-my-feature`).
- Each branch is reviewed and merged into the stable series branch (e.g. `18.0`).
- Releases are **decoupled from individual merges** — a release is a deliberate
  decision made when the maintainer considers the stable branch ready to snapshot.
  Multiple feature PRs, fixes, and translation updates may all land on stable before
  a single release is cut.

### Making a release

When the stable branch is in a state worth pinning:

```bash
# Standard release — auto-detects bump level, generates changelog, tags, pushes:
odood repo release --changelog --push
```

`odood repo release` will:

1. Fetch remote tags to find the latest release (union of local and remote, to handle
   tags pushed by others not yet fetched locally).
2. Verify that every addon changed since the last release tag has a bumped version
   (safety gate — normally already satisfied by CI).
3. Compute the next repository version from the aggregate addon changes
   (the most significant change wins):
   - Any addon had a **major** bump, or an addon was **removed** → `X` incremented, `Y` and `Z` reset to `0`.
   - Any addon had a **minor** or **patch** bump, or an addon was **added** → `Y` incremented, `Z` reset to `0`.
4. Optionally generate `CHANGELOG.md` / `CHANGELOG.latest.md` and commit them.
5. Create a git tag with the new version.
6. Push the branch and tag if `--push` is given.

> **`--push` branch guard:** When `--push` is supplied for a standard release,
> the command requires the current branch to match the stable series branch
> (e.g. `18.0`). This prevents accidentally tagging from a feature branch. The
> guard does not apply to `--patch`, which is a conscious, explicit choice.

Override the auto-detected bump level when needed:

```bash
odood repo release --major   # force X bump
odood repo release --minor   # force Y bump
odood repo release --patch   # force Z bump (mainline patch release)
```

> `--patch` is the **mainline patch**: a deliberate `Z` bump on top of the
> latest serie release (e.g. a small fix you want to ship as `18.0.2.1.1`
> without a minor bump). It must be requested explicitly — auto-detection never
> produces a `Z` bump — and, being explicit, carries no branch restriction.
>
> To patch an *older* release while the stable branch has already moved on, use
> the [hotfix flow](#hotfix-flow) (`odood repo hotfix`) instead —
> it builds on the right patch chain rather than the latest serie tag.

When nothing changed since the last tag, `release` exits successfully without
creating a tag. In automation, add `--fail-nothing-to-release` to exit with
code `1` instead — handy for gating downstream steps that should only run when a
release was actually cut. (`hotfix release` accepts the same flag.)

### First release

For a repository that has never been tagged:

```bash
odood repo release --initial
```

This creates tag `<serie>.1.0.0` without inspecting addon changes. The first
*non-`--initial`* release bootstraps from `<serie>.1.0.0` and then applies the
bump, so it lands **above** `<serie>.1.0.0` (e.g. `<serie>.1.1.0` for a minor
bump) — never `<serie>.1.0.0` itself.

---

## Hotfix Flow

A hotfix is a targeted fix applied to an already-released version, independent of
ongoing development on the stable branch.

> **Hotfix vs. mainline patch.** Both bump `Z`, but they differ in their *base*.
> A mainline `release --patch` builds on the latest serie release — use it for a
> quick fix on top of the current line. The hotfix flow builds on a specific
> older patch chain via a dedicated branch — use it when stable has already
> moved past the release you need to fix.

**When to use:** A critical bug is found in the deployed version `18.0.2.1.0`, but
the stable branch already has several changes that are not ready to ship. You need
to release a fix as `18.0.2.1.1` without including the unreleased work.

### Conceptual workflow

```
stable branch (18.0):

  ... ── [2.1.0] ──── [ongoing work] ─── [ongoing work] ──→  (not ready)
              │
              └── hotfix/18.0.2.1.x
                       │
                    [fix commit]
                       │
                    [2.1.1 tag]  ←── hotfix release here
                       │
                    cherry-pick back to stable branch
```

The entire hotfix lifecycle lives under the `odood repo hotfix` command group
(`start` → `check` → `release`), keeping it separate from mainline releases.

### Step-by-step

1. **Create a hotfix branch** with `odood repo hotfix start`:

   ```bash
   odood repo hotfix start --from=18.0.2.1.0
   ```

   This validates the primary tag, finds the latest existing tag in the
   `18.0.2.1.*` chain (so subsequent patches like `18.0.2.1.2` are handled
   correctly), creates `hotfix/18.0.2.1.x` from it, and prints next steps.

   The `--from` argument always takes the **primary release** (`Z == 0`), never
   an intermediate hotfix.

   `start` is non-destructive when the branch already exists: it **switches to
   the existing local branch** (preserving any work-in-progress), or — if the
   branch exists only on `origin` — **checks out a tracking branch** from it
   rather than creating a divergent local one. A fresh branch is created only
   when none exists locally or remotely.

2. **Apply the fix.** Commit normally; bump affected addon versions.

   Optionally preview the check before releasing — run from the hotfix branch:

   ```bash
   odood repo hotfix check --ignore-translations
   ```

   This compares against the latest tag in the branch's patch chain — exactly
   what `hotfix release` will verify.

3. **Release the patch** — from the hotfix branch:

   ```bash
   odood repo hotfix release --changelog --push
   ```

   `hotfix release` derives the chain from the current `hotfix/A.B.X.Y.x`
   branch, takes the chain's latest tag as the base, and bumps `Z` — producing
   e.g. `18.0.2.1.1`. Because the base is the chain (not the latest serie tag),
   the patch builds on the old release even when stable has moved on. It refuses
   to run when not on a hotfix branch.

> **In CI:** both `hotfix check` and `hotfix release` derive the chain from the
> branch name, so they must run with the `hotfix/A.B.X.Y.x` branch **checked
> out** — they cannot work from a detached `HEAD` (e.g. a tag-triggered
> pipeline). Use a branch-triggered job for the hotfix branch.

4. **Cherry-pick the fix back** to the stable branch:

   ```bash
   git checkout 18.0
   git cherry-pick <fix-commit-hash>
   ```

   Version conflicts during cherry-pick are expected and mechanical: always keep
   the stable branch's (higher) addon version.

5. **Do not merge the hotfix branch into stable.** Cherry-pick individual fix
   commits only. The hotfix branch diverged from an old release tag; a merge would
   bring in stale version history.

---

## Versioning Invariants

| Property | Rule |
|----------|------|
| Auto-detected release | Always ends in `.0` (e.g. `18.0.2.1.0`) |
| Patch release | Only `Z` changes; `X.Y` stays equal to the release it builds on (e.g. `18.0.2.1.1`) |
| Patch chain | All patches sharing the same `A.B.X.Y` prefix build on the same `X.Y` release |

These invariants make it trivial to:
- Tell a patch release from a primary release: `Z > 0` means patch (a hotfix, or a deliberate patch on stable); `Z == 0` means primary.
- Find the latest release for a series (including patches): take the max over all `A.B.*` tags.
- Find all patches for a given primary release: filter tags by `A.B.X.Y.*` and sort.

---

## Caveats

A few sharp edges worth knowing:

- **The patch chain is a tag namespace, not a single branch.** `release --patch`
  patches the latest serie release; `hotfix release` patches the chain its branch
  is based on (`getLatestPatch` picks the chain's highest tag, so it always counts
  up). When both target the same `A.B.X.Y` chain, their `Z` numbers interleave
  across divergent commits — a mainline patch may take `18.0.2.1.1`, then a hotfix
  on the same primary becomes `18.0.2.1.2` on a different commit. Tags never
  collide, but read the chain as "all patches built on the `X.Y` release", not as
  one linear history.

- **A mainline release bases on the highest serie tag.** `release` and
  `release --patch` compare against — and bump from — the numerically latest
  serie tag. If you hotfix the latest release (`18.0.2.1.0` → `18.0.2.1.1`) and
  then run a normal release on stable *before* cherry-picking the fix back, that
  hotfix tag becomes the base, and the version check may report "current version
  must be greater than origin" for addons the hotfix bumped. Cherry-picking the
  fix back to stable first (step 4 of the hotfix flow) resolves this — treat the
  error as a reminder to back-port.

---

## Pre-release version check

Before releasing, you can preview exactly what `odood repo release` will verify:

```bash
odood repo check-versions --since-last-release --ignore-translations
```

`check-versions` chooses its comparison baseline from the flags:

| Command | Compares against | Use for |
|---------|------------------|---------|
| `check-versions` | stable branch tip (`origin/<serie>`) | CI on a PR |
| `check-versions --since-last-release` | the latest release tag for the serie (any chain, including patches) | previewing a standard `release` |
| `hotfix check` | the latest tag in the current hotfix branch's patch chain | previewing `hotfix release` |

To preview a hotfix instead, run `odood repo hotfix check` from the hotfix
branch — it mirrors what `hotfix release` will verify (see the
[Hotfix flow](#hotfix-flow)).

---

## CI setup for addon repositories

Add a version check job to your PR pipeline to catch unbumped addon versions before
they reach the stable branch.

### GitHub Actions

```yaml
name: Check addon versions

on:
  pull_request:
    branches:
      - '18.0'

jobs:
  check-versions:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/katyukha/odood/odoo/18.0:latest
    steps:
      - uses: actions/checkout@v6

      - name: Add safe directory
        run: git config --global --add safe.directory "$(pwd)"

      - name: Check addon versions
        run: odood repo check-versions --ignore-translations
```

### GitLab CI

```yaml
check_addon_versions:
  image: ghcr.io/katyukha/odood/odoo/18.0:latest
  before_script:
    - git config --global --add safe.directory "$(pwd)"
  script:
    - odood repo check-versions --ignore-translations
  only:
    - merge_requests
```

Both examples use the Odood Docker image (which includes a pre-configured Odoo
installation and the `odood` binary). The check compares the PR branch against
`origin/<serie>` — the stable branch — and fails if any changed addon has not had
its version bumped.
