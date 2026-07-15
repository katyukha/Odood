module odood.lib.addons.repository;

private import std.logger: warningf, infof;
private import std.algorithm: canFind, map, filter, maxElement, sort;
private import std.format: format;
private import std.typecons: Nullable, nullable;
private import std.exception: enforce;
private import std.array: appender, array, split;
private import std.string: strip, join;
private import std.json: JSONValue;
private import std.regex: replaceFirst, regex;
private import std.datetime.date: DateTime;
private import std.datetime.systime: Clock;

private import darktemple: renderFile;

private import versioned: Version, VersionPart;
private import thepath: Path;

private import odood.utils.addons.addon: OdooAddon, findAddons;
private import odood.utils.addons.addon_changelog:
    OdooAddonChangelogEntry, matchChangelogFileVersion;
private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.addons.addon_manifest: tryParseOdooManifest;
private import odood.exception: OdoodException;
private import odood.git: GitRepository, GIT_REF_WORKTREE;
private import odood.lib.addons.changes: AddonRepositoryChanges;


struct AddonCheckError {
    string addon_name;
    string[] messages;
}

/** Result of a version-check run across changed addons in a repository. **/
struct AddonVersionCheckResult {
    bool ok = true;                  /// true if all changed addons passed all checks
    AddonRepositoryChanges changes;  /// changes collected by checkVersions; null only before first run
    AddonCheckError[] errors;        /// one entry per failing addon, possibly with multiple messages

    @property bool has_changes() const {
        return changes !is null && changes.has_changes;
    }

    void addError(in string addon_name, in string message) {
        ok = false;
        foreach(ref e; errors)
            if (e.addon_name == addon_name) { e.messages ~= message; return; }
        errors ~= AddonCheckError(addon_name, [message]);
    }
}

/** How strict the changelog check is. **/
enum ChangelogRequirement {
    all,  /// every updated addon must have a changelog entry
    any,  /// at least one updated addon must have a changelog entry
}

/** Result of a changelog-check run across changed addons in a repository. **/
struct ChangelogCheckResult {
    bool ok = true;                  /// true if the changelog requirement is satisfied
    AddonRepositoryChanges changes;  /// changes collected by ensureChangelog; null only before first run
    string[] addons_missing_changelog;  /// updated addons without a changelog entry for the bump

    @property bool has_changes() const {
        return changes !is null && changes.has_changes;
    }
}

/** Result of a successful prepareRelease call.
  *
  * Carries the new version, the full changes object (for changelog generation),
  * and the start_ref used (needed to restore CHANGELOG.md history).
  **/
struct PrepareReleaseResult {
    OdooStdVersion new_version;
    AddonRepositoryChanges addon_changes;
    string start_ref;
}

/// Addon identity at a specific git ref: path relative to repo root, name, version.
private struct AddonInfo {
    Path path;
    string name;
    OdooStdVersion addon_version;
}



class AddonRepository : GitRepository{

    @disable this();

    this(in GitRepository repo) {
        super(repo.path);
    }

    this(T...)(auto ref T args) {
        super(args);
    }

    /** Scan repository for addons and return array of odoo addons,
      * found in this repo.
      * This method searches for addons recursively by default.
      *
      * Params:
      *     recursive = If set to true, search for addons recursively inside repo.
      *         Otherwise, scan only the root directory of the repo for addons.
      **/
    auto addons(in bool recursive=true) const {
        return findAddons(path, recursive);
    }

    /** Serialize repository metadata to JSON: path, current branch,
      * remote url, derived Odoo serie (from the branch name), and addon count.
      *
      * Intended for `odood repo list --json` and tooling. Fields that are not
      * available (e.g. no `origin` remote, detached HEAD) are simply omitted.
      * The remote url is credential-stripped (`GitURL.toString`).
      **/
    JSONValue toJSON() const {
        JSONValue j = JSONValue.emptyObject;
        j["path"] = this.path.toString;

        auto branch = this.getCurrBranch;
        if (!branch.isNull) {
            j["branch"] = branch.get;
            // Branch naming convention is `{serie}` or `{serie}-{feature}`.
            auto serie = OdooSerie(branch.get.split("-")[0]);
            if (serie.isValid)
                j["serie"] = serie.toString;
        }

        try {
            j["remote"] = this.getRemoteUrl.toString;
        } catch (Exception) { /* no remote configured */ }

        j["addons_count"] = this.addons.length;
        return j;
    }

    /** Get version of addon in specified commit
      *
      * Params:
      *     addon = Addon to get version for
      *     rev = git revision to get addon version for
      **/
    Nullable!OdooStdVersion getAddonVersion(in Path addon_path, in string rev) const {
        enforce!OdoodException(
            addon_path.isInside(this.path),
            "Addon must be inside repo");
        auto g_path = addon_path.relativeTo(this.path);
        auto g_manifest_path = g_path.join("__manifest__.py");
        if (!this.isFileExists(g_manifest_path, rev))
            g_manifest_path = g_path.join("__openerp__.py");
        if (!this.isFileExists(g_manifest_path, rev))
            // File not exists in specified revision
            return Nullable!OdooStdVersion.init;

        auto manifest = tryParseOdooManifest(this.getContent(g_manifest_path, rev));
        if (manifest.isNull)
            // Cannot read manifest in specified revision
            return Nullable!OdooStdVersion.init;

        return manifest.get.module_version.nullable;
    }

    /// ditto
    Nullable!OdooStdVersion getAddonVersion(in OdooAddon addon, in string rev) const {
        return getAddonVersion(addon.path, rev);
    }

    /// ditto
    Nullable!OdooStdVersion getAddonVersion(in Path addon_path) const {
        return getAddonVersion(addon_path, GIT_REF_WORKTREE);
    }

    /// ditto
    Nullable!OdooStdVersion getAddonVersion(in OdooAddon addon) const {
        return getAddonVersion(addon, GIT_REF_WORKTREE);
    }

    /** Get changed addons.
        Thus method mostly used by dev utils to automate some tasks
        interacting with git.
      **/
    auto getChangedModules(in string start_ref, in string end_ref, in bool ignore_translations=true) const {
        Path[] changedAddonPaths;
        foreach(path; getChangedFiles(start_ref, end_ref, ignore_translations ? [":(exclude)*.po", ":(exclude)*.pot"] : [])) {
           // Prepend the repo root so searchFileUp resolves correctly regardless of CWD.
           auto abs_path = this.path.join(path);
           auto manifest_path = abs_path.searchFileUp("__manifest__.py");
           if (manifest_path.isNull)
               manifest_path = abs_path.searchFileUp("__openerp__.py");
           if (manifest_path.isNull)
               continue;

           if (!changedAddonPaths.canFind(manifest_path.get.parent))
               changedAddonPaths ~= [manifest_path.get.parent];
        }
        return changedAddonPaths.map!((p) => new OdooAddon(p));
    }

    /// ditto
    auto getChangedModules(in string start_ref, in bool ignore_translations=true) const {
        return getChangedModules(
            start_ref: start_ref,
            end_ref: GIT_REF_WORKTREE,
            ignore_translations: ignore_translations);
    }

    /** Walk up from file_path to find the addon that contains it at the given ref.
      *
      * Works for both git refs and GIT_REF_WORKTREE (filesystem).
      * Returns null when the file does not belong to any addon.
      **/
    private Nullable!AddonInfo findAddonInRef(in Path file_path, in string rev) const {
        foreach(mname; ["__manifest__.py", "__openerp__.py"]) {
            auto mpath = searchFileUp(file_path.parent(false), mname, rev);
            if (mpath.isNull) continue;
            auto parsed = tryParseOdooManifest(getContent(mpath.get, rev));
            if (!parsed.isNull)
                return AddonInfo(
                    mpath.get.parent(false),
                    mpath.get.parent(false).baseName,  // directory name = Odoo module technical name
                    parsed.get.module_version).nullable;
            // Manifest file found but unparseable — stop.
            return Nullable!AddonInfo.init;
        }
        return Nullable!AddonInfo.init;
    }

    /** Read changelog entries for an addon at the given ref.
      *
      * For the worktree the changelog files are read from the filesystem; for
      * any other ref the addon's `changelog/` directory is listed in that ref
      * via git and each entry's content is read from the ref. This makes
      * changelog collection work for arbitrary end refs, not just the worktree.
      *
      * Params:
      *     addon_path = path to the addon, relative to the repo root.
      *     rev        = git ref to read from (or GIT_REF_WORKTREE).
      *     start_ver  = if set, entries with version <= start_ver are excluded.
      **/
    OdooAddonChangelogEntry[] readAddonChangelog(
            in Path addon_path, in string rev,
            in Nullable!Version start_ver=Nullable!Version.init) const {
        if (rev == GIT_REF_WORKTREE)
            return new OdooAddon(this.path.join(addon_path))
                .readChangelogEntries(start_ver: start_ver);

        auto changelog_dir = addon_path.join("changelog");
        OdooAddonChangelogEntry[] entries;
        foreach (p; listDir(changelog_dir, rev)) {
            // The version is in the file name, so entries at or below start_ver
            // are skipped before reading content from git (one `git show` per
            // file).
            auto ver = matchChangelogFileVersion(p.baseName);
            if (ver.isNull)
                continue;
            if (!start_ver.isNull && start_ver.get >= ver.get)
                continue;
            entries ~= OdooAddonChangelogEntry(
                ver.get, getContent(changelog_dir.join(p.baseName), rev));
        }
        entries.sort!("a > b");
        return entries;
    }

    /** Collect addon-level changes between start_ref and end_ref.
      *
      * For each changed file, the containing addon is looked up independently
      * in start_ref and end_ref using findAddonInRef. Results are matched by
      * addon name, which makes moves transparent: an addon at a different path
      * in end_ref than in start_ref is treated as an update, not remove + add.
      *
      * Does NOT call postProcess() — the caller decides whether to do that.
      *
      * Params:
      *     start_ref           = Git ref to compare against.
      *     end_ref             = Git ref for the current state. Defaults to worktree.
      *     ignore_translations = Exclude .po/.pot files when detecting changes.
      *     initial_version     = Seed value for AddonRepositoryChanges.repo_version.
      *                           Pass OdooStdVersion.init when not needed.
      **/
    AddonRepositoryChanges collectChanges(
            in string start_ref,
            in string end_ref = GIT_REF_WORKTREE,
            in bool ignore_translations = true,
            in OdooStdVersion initial_version = OdooStdVersion.init) const {
        auto changes = new AddonRepositoryChanges(initial_version);
        auto path_filters = ignore_translations
            ? [":(exclude)*.po", ":(exclude)*.pot"]
            : cast(string[])[];

        AddonInfo[string] start_map;
        AddonInfo[string] end_map;

        foreach(file; getChangedFiles(start_ref, end_ref, path_filters)) {
            auto in_start = findAddonInRef(file, start_ref);
            if (!in_start.isNull)
                start_map[in_start.get.name] = in_start.get;

            auto in_end = findAddonInRef(file, end_ref);
            if (!in_end.isNull) {
                auto end_name = in_end.get.name;
                enforce!OdoodException(
                    end_name !in end_map
                        || end_map[end_name].path == in_end.get.path,
                    ("Addon '%s' found at two paths in end ref '%s': %s and %s. "
                    ~ "A repository must not contain duplicate addon names.").format(
                        end_name, end_ref,
                        end_map[end_name].path, in_end.get.path));
                end_map[end_name] = in_end.get;
            }
        }

        foreach(name, info; start_map)
            if (name !in end_map)
                changes.logAddonRemoved(name);

        foreach(name, end_info; end_map) {
            if (name !in start_map) {
                changes.logAddonAdded(name, end_info.path, end_info.addon_version);
            } else {
                auto start_info = start_map[name];
                // Read changelog entries newer than the start version, from the
                // end ref (works for both the worktree and historical refs).
                // Changelogs are only supported for standard-versioned addons.
                auto changelog = start_info.addon_version.isStandard
                    ? readAddonChangelog(
                        end_info.path, end_ref,
                        cast(Nullable!Version)
                            start_info.addon_version.semver.nullable)
                    : cast(OdooAddonChangelogEntry[]) [];
                changes.logAddonUpdated(
                    name,
                    start_info.path,
                    end_info.path,
                    start_info.addon_version,
                    end_info.addon_version,
                    changelog);
            }
        }

        return changes;
    }

    /** Check that all addons changed between start_ref and end_ref have
      * properly bumped their version numbers.
      *
      * For each changed addon:
      * - Skips new addons (not present in start_ref).
      * - Skips removed addons (not present in end_ref).
      * - Fails if the current version is non-standard.
      * - Skips if the origin version is non-standard.
      * - Fails if the addon serie doesn't match expected_serie
      *   (only when expected_serie.isValid).
      * - Fails if current version is not greater than the origin version.
      *
      * Params:
      *     expected_serie = Odoo serie to validate addon versions against.
      *         Pass OdooSerie.init to skip the serie check.
      *     start_ref      = Git ref to compare against (e.g. "origin/16.0").
      *     end_ref        = Git ref for the current state. Defaults to worktree.
      *     ignore_translations = Exclude .po/.pot files when detecting changes.
      *
      * Returns: AddonVersionCheckResult with ok=false and errors populated
      *          for each failing addon.
      **/
    AddonVersionCheckResult checkVersions(
            in OdooSerie expected_serie,
            in string start_ref,
            in string end_ref = GIT_REF_WORKTREE,
            in bool ignore_translations = true) const {
        AddonVersionCheckResult result;

        auto changes = collectChanges(start_ref, end_ref, ignore_translations);
        result.changes = changes;

        foreach(addon; changes.addons_updated) {
            auto start_version = addon.old_version;
            auto end_version   = addon.new_version;

            if (!end_version.isStandard) {
                result.addError(
                    addon.name,
                    ("Non-standard current version (%s). " ~
                     "Please use standard versions in format %s.X.Y.Z.").format(
                        end_version,
                        expected_serie.isValid ? expected_serie.toString : "M.m"));
                continue;
            }

            if (!start_version.isStandard)
                continue;

            if (expected_serie.isValid && end_version.serie != expected_serie)
                result.addError(
                    addon.name,
                    "Serie (%s) does not match expected serie (%s).".format(
                        end_version.serie, expected_serie));

            if (start_version >= end_version)
                result.addError(
                    addon.name,
                    "Current version (%s) must be greater than stable version (%s).".format(
                        end_version, start_version));
        }
        return result;
    }

    /** Check that addons changed between start_ref and end_ref carry a
      * changelog entry for their version bump.
      *
      * Only *updated* addons are subject to the requirement; newly added and
      * removed addons are exempt (an added addon's whole history is new, a
      * removed one has none). An updated addon "has a changelog" when it
      * carries a changelog entry newer than its start-ref version — exactly the
      * entries that feed release-changelog generation.
      *
      * Params:
      *     start_ref           = Git ref to compare against (e.g. "origin/16.0").
      *     end_ref             = Git ref for the current state. Defaults to worktree.
      *     require             = all  → every updated addon must have a changelog;
      *                           any  → at least one updated addon must have one.
      *     ignore_translations = Exclude .po/.pot files when detecting changes.
      *
      * Returns: ChangelogCheckResult with ok=false and addons_missing_changelog
      *          populated when the requirement is not met.
      **/
    ChangelogCheckResult ensureChangelog(
            in string start_ref,
            in string end_ref = GIT_REF_WORKTREE,
            in ChangelogRequirement require = ChangelogRequirement.all,
            in bool ignore_translations = true) const {
        ChangelogCheckResult result;

        auto changes = collectChanges(start_ref, end_ref, ignore_translations);
        result.changes = changes;

        // Updated addons that carry a changelog entry covering the bump.
        bool[string] has_changelog;
        foreach(nc; changes.notable_changes)
            has_changelog[nc.name] = true;

        foreach(addon; changes.addons_updated)
            if (addon.name !in has_changelog)
                result.addons_missing_changelog ~= addon.name;

        final switch (require) {
            case ChangelogRequirement.all:
                // Every updated addon must have a changelog.
                result.ok = result.addons_missing_changelog.length == 0;
                break;
            case ChangelogRequirement.any:
                // At least one updated addon must have a changelog. With no
                // updated addons there is nothing to require → pass.
                result.ok = changes.addons_updated.length == 0
                    || has_changelog.length > 0;
                break;
        }
        return result;
    }

    /** Get the latest release tag for a given Odoo serie.
      *
      * Checks both local and remote tags (same as prepareRelease).
      * Returns null if no release tags exist for this serie.
      *
      * Params:
      *     serie = Odoo serie (e.g. OdooSerie("18.0")).
      **/
    Nullable!OdooStdVersion getLatestRelease(in OdooSerie serie) const {
        string[] all_tags = listLocalTags();
        if (hasRemoteUrl("origin")) {
            try {
                all_tags ~= listRemoteTags("origin");
            } catch (Exception e) {
                warningf("Cannot list remote tags (using local only): %s", e.msg);
            }
        }

        auto matching = all_tags
            .map!(t => OdooStdVersion(t))
            .filter!(v => v.isStandard && v.serie == serie)
            .array;

        if (matching.length == 0)
            return Nullable!OdooStdVersion.init;

        return matching.maxElement.nullable;
    }

    /** Find the latest existing tag in the patch chain that `chain_version`
      * belongs to.
      *
      * A "patch chain" is all tags A.B.X.Y.* sharing the same serie, major, and
      * minor. It includes the primary release (Z == 0) and any subsequent
      * patches/hotfixes (Z > 0). The patch segment of `chain_version` is
      * ignored — any member of the chain identifies it, so passing the primary
      * (`18.0.2.1.0`) or an existing patch (`18.0.2.1.3`) selects the same chain.
      *
      * Returns null if no tag in the chain exists (not even the primary),
      * indicating the chain was never released.
      *
      * Checks both local and remote tags.
      *
      * Params:
      *     chain_version = Any standard version identifying the chain (its `Z`
      *                     is ignored).
      **/
    Nullable!OdooStdVersion getLatestPatch(in OdooStdVersion chain_version) const
    in (chain_version.isStandard) {
        string[] all_tags = listLocalTags();
        if (hasRemoteUrl("origin")) {
            try {
                all_tags ~= listRemoteTags("origin");
            } catch (Exception e) {
                warningf("Cannot list remote tags (using local only): %s", e.msg);
            }
        }

        auto matching = all_tags
            .map!(t => OdooStdVersion(t))
            .filter!(v => v.isStandard
                       && v.serie == chain_version.serie
                       && v.major == chain_version.major
                       && v.minor == chain_version.minor)
            .array;

        if (matching.length == 0)
            return Nullable!OdooStdVersion.init;

        return matching.maxElement.nullable;
    }

    /** Return the version for the very first release of this repository.
      *
      * Throws if a matching release tag already exists locally or on the
      * remote, to prevent accidentally overwriting an established release
      * history.
      *
      * The caller handles tag → push.
      *
      * Params:
      *     serie = Odoo serie (e.g. OdooSerie("18.0")).
      *
      * Returns: OdooStdVersion(serie, 1, 0, 0).
      **/
    OdooStdVersion initialRelease(in OdooSerie serie) const {
        auto existing = getLatestRelease(serie);
        enforce!OdoodException(
            existing.isNull,
            ("Repository already has release tags for serie %s (latest: %s). "
            ~ "Use 'odood repo release' for subsequent releases.").format(
                serie, existing.get));

        return OdooStdVersion(serie, 1, 0, 0);
    }

    /** Compute the next repo release version.
      *
      * Finds the latest release tag by merging local tags and remote tags.
      * Using both covers two edge cases: an unpushed local tag from a previous
      * step in this flow, and a tag pushed by someone else not yet fetched.
      * If no matching tag exists anywhere, compares against `origin/<serie>`
      * and bootstraps the version at `<serie>.1.0.0`.
      *
      * The tag name is the sole source of truth for the current version —
      * no VERSION file is written or staged.  The caller handles tag → push.
      *
      * Params:
      *     serie               = Odoo serie (e.g. OdooSerie("17.0")).
      *     override_part       = When set, force this bump level instead of
      *                           auto-detecting from changes.
      *     ignore_translations = Exclude .po/.pot files when detecting changes.
      *     base_version        = When set, use this exact version as both the
      *                           comparison base and the version to bump from,
      *                           instead of the latest-serie-tag lookup. Used by
      *                           the hotfix flow to pin a specific patch chain.
      *
      * Returns: null if no changed addons detected; the new version otherwise.
      **/
    Nullable!PrepareReleaseResult prepareRelease(
            in OdooSerie serie,
            in Nullable!VersionPart override_part = Nullable!VersionPart.init,
            in bool ignore_translations = true,
            in Nullable!OdooStdVersion base_version = Nullable!OdooStdVersion.init) const {
        // Defaults cover the bootstrap case (no prior tags): compare against the
        // origin branch and seed the version at <serie>.1.0.0.
        string start_ref = "origin/%s".format(serie);
        auto initial_version = OdooStdVersion(serie, 1, 0, 0);

        if (!base_version.isNull) {
            // Explicit base (hotfix chain): compare against and bump from it.
            initial_version = base_version.get;
            start_ref = base_version.get.toString;
        } else {
            // 1. Union of local and remote tags — see initialRelease for rationale.
            string[] all_tags = listLocalTags();
            if (hasRemoteUrl("origin")) {
                try {
                    all_tags ~= listRemoteTags("origin");
                } catch (Exception e) {
                    warningf("Cannot list remote tags (using local only): %s", e.msg);
                }
            }

            auto matching_versions = all_tags
                .map!(t => OdooStdVersion(t))
                .filter!(v => v.isStandard && v.serie == serie)
                .array;

            if (matching_versions.length > 0) {
                auto latest = matching_versions.maxElement;
                start_ref = latest.toString;
                initial_version = latest;  // tag name is the authoritative version
            }
        }

        // 2. Verify all changed addons have bumped versions.
        auto check = checkVersions(serie, start_ref, GIT_REF_WORKTREE, ignore_translations);
        if (!check.ok) {
            auto msgs = check.errors
                .map!(e => "%s: %s".format(e.addon_name, e.messages.join("; ")))
                .array;
            enforce!OdoodException(
                false,
                "Version check failed before release:\n" ~ msgs.join("\n"));
        }

        if (!check.has_changes)
            return Nullable!PrepareReleaseResult.init;

        // 3. Reuse changes already collected by checkVersions; seed the repo version.
        auto changes = check.changes;
        changes.repo_version = initial_version;

        if (!override_part.isNull)
            changes.repo_version = changes.repo_version.incVersion(override_part.get);
        else
            changes.postProcess();

        return PrepareReleaseResult(changes.repo_version, changes, start_ref).nullable;
    }

    /** Generate CHANGELOG.md and CHANGELOG.latest.md for a repo release.
      *
      * Restores CHANGELOG.md from result.start_ref (if present) before
      * prepending the new release section, so history is preserved.
      * Stages both files; does NOT commit — the caller decides.
      *
      * Params:
      *     result = The PrepareReleaseResult returned by prepareRelease.
      **/
    void generateChangelog(in PrepareReleaseResult result) {
        infof("Generating changelog for release %s ...", result.new_version);

        // Local alias required: darktemple binds template arg names to template vars.
        // The template uses {{ changes.xxx }}, so the D variable must be named 'changes'.
        auto changes = result.addon_changes;
        auto release_date = cast(DateTime)Clock.currTime();
        auto changelog_text = renderFile!(
            "templates/repository/changelog.md.tmpl",
            changes, release_date);

        auto changelog_path = path.join("CHANGELOG.md");
        auto changelog_latest_path = path.join("CHANGELOG.latest.md");

        changelog_latest_path.writeFile(changelog_text);
        add(changelog_latest_path);

        // Restore CHANGELOG.md from start_ref so we prepend, not overwrite.
        if (isFileExists(changelog_path, result.start_ref))
            checkoutFile(result.start_ref, true, changelog_path);
        else
            remove(changelog_path, force: true, ignore_unmatch: true);

        if (changelog_path.exists) {
            auto existing = changelog_path.readFileText
                .replaceFirst(regex("# Changelog\n"), changelog_text);
            changelog_path.writeFile(existing);
        } else {
            changelog_path.writeFile(changelog_text);
        }

        add(changelog_path);
        infof("Changelog generated.");
    }
}

unittest {
    import std.algorithm: map, canFind, filter;
    import std.array: array;
    import unit_threaded.assertions;
    import thepath: createTempPath;

    auto root = createTempPath;
    scope(exit) root.remove();

    auto repo = new AddonRepository(GitRepository.initialize(root.join("test-repo")));
    auto repo_path = repo.path;

    // Set up two addons and one plain directory
    foreach(name; ["addon_a", "addon_b"]) {
        repo_path.join(name).mkdir(false);
        repo_path.join(name, "__init__.py").writeFile("");
        repo_path.join(name, "__manifest__.py").writeFile(
            `{"name": "%s", "version": "17.0.1.0.0", "depends": ["base"]}`.format(name));
    }
    repo_path.join("not_an_addon").mkdir(false);
    repo_path.join("not_an_addon", "README.txt").writeFile("hello");

    repo.add(repo_path.join("addon_a"));
    repo.add(repo_path.join("addon_b"));
    repo.add(repo_path.join("not_an_addon"));
    repo.commit("Initial commit");
    auto rev_v1 = repo.getCurrCommit();

    // addons() finds only real addons, ignores plain dirs
    auto addons_v1 = repo.addons();
    addons_v1.length.should == 2;
    addons_v1.map!((a) => a.name).canFind("addon_a").shouldBeTrue;
    addons_v1.map!((a) => a.name).canFind("addon_b").shouldBeTrue;
    addons_v1.map!((a) => a.name).canFind("not_an_addon").shouldBeFalse;

    // getAddonVersion — current worktree
    auto addon_a = addons_v1.filter!((a) => a.name == "addon_a").front;
    repo.getAddonVersion(addon_a).isNull.shouldBeFalse;
    repo.getAddonVersion(addon_a).get.toString.should == "17.0.1.0.0";

    // Update addon_a manifest version; add a new file to addon_b (non-manifest change)
    repo_path.join("addon_a", "__manifest__.py").writeFile(
        `{"name": "addon_a", "version": "17.0.1.1.0", "depends": ["base"]}`);
    repo_path.join("addon_b", "models.py").writeFile("# models");

    repo.add(repo_path.join("addon_a", "__manifest__.py"));
    repo.add(repo_path.join("addon_b", "models.py"));
    repo.commit("Update addons");
    auto rev_v2 = repo.getCurrCommit();

    // getAddonVersion — current version updated
    repo.getAddonVersion(addon_a).get.toString.should == "17.0.1.1.0";

    // getAddonVersion — historical revision returns old version
    repo.getAddonVersion(addon_a, rev_v1).isNull.shouldBeFalse;
    repo.getAddonVersion(addon_a, rev_v1).get.toString.should == "17.0.1.0.0";

    // getChangedModules — both addons changed between v1 and v2
    auto changed = repo.getChangedModules(rev_v1, rev_v2).array;
    changed.length.should == 2;
    changed.map!((a) => a.name).canFind("addon_a").shouldBeTrue;
    changed.map!((a) => a.name).canFind("addon_b").shouldBeTrue;

    // getChangedModules — nothing changed since v2
    repo.getChangedModules(rev_v2).array.length.should == 0;

    // collectChanges — both addons updated between v1 and v2
    auto cc_v1_v2 = repo.collectChanges(rev_v1, rev_v2);
    cc_v1_v2.addons_added.length.should == 0;
    cc_v1_v2.addons_removed.length.should == 0;
    cc_v1_v2.addons_updated.length.should == 2;
    cc_v1_v2.addons_updated.map!((a) => a.name).canFind("addon_a").shouldBeTrue;
    cc_v1_v2.addons_updated.map!((a) => a.name).canFind("addon_b").shouldBeTrue;

    // collectChanges — new addon appears as added
    repo_path.join("addon_c").mkdir(false);
    repo_path.join("addon_c", "__init__.py").writeFile("");
    repo_path.join("addon_c", "__manifest__.py").writeFile(
        `{"name": "addon_c", "version": "17.0.1.0.0", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_c"));
    repo.commit("Add addon_c");
    auto rev_v3 = repo.getCurrCommit();

    auto cc_v2_v3 = repo.collectChanges(rev_v2, rev_v3);
    cc_v2_v3.addons_added.length.should == 1;
    cc_v2_v3.addons_added[0].name.should == "addon_c";
    cc_v2_v3.addons_removed.length.should == 0;
    cc_v2_v3.addons_updated.length.should == 0;

    // collectChanges — removed addon appears as removed
    repo.remove(repo_path.join("addon_c"), recursive: true);
    repo.commit("Remove addon_c");
    auto rev_v4 = repo.getCurrCommit();

    auto cc_v3_v4 = repo.collectChanges(rev_v3, rev_v4);
    cc_v3_v4.addons_added.length.should == 0;
    cc_v3_v4.addons_removed.length.should == 1;
    cc_v3_v4.addons_removed[0].should == "addon_c";
    cc_v3_v4.addons_updated.length.should == 0;

    // collectChanges — moved addon (into subdir) appears as updated, not remove+add
    repo_path.join("addons").mkdir(false);
    repo_path.join("addon_b", "__manifest__.py").writeFile(
        `{"name": "addon_b", "version": "17.0.1.0.1", "depends": ["base"]}`);
    repo_path.join("addons", "addon_b").mkdir(false);
    repo_path.join("addons", "addon_b", "__init__.py").writeFile("");
    repo_path.join("addons", "addon_b", "__manifest__.py").writeFile(
        `{"name": "addon_b", "version": "17.0.1.0.1", "depends": ["base"]}`);
    repo_path.join("addons", "addon_b", "models.py").writeFile("# models");
    repo.remove(repo_path.join("addon_b"), recursive: true, force: true);
    repo.add(repo_path.join("addons", "addon_b"));
    repo.commit("Move addon_b to addons/");
    auto rev_v5 = repo.getCurrCommit();

    auto cc_v4_v5 = repo.collectChanges(rev_v4, rev_v5);
    cc_v4_v5.addons_added.length.should == 0;
    cc_v4_v5.addons_removed.length.should == 0;
    cc_v4_v5.addons_updated.length.should == 1;  // move treated as update
    cc_v4_v5.addons_updated[0].name.should == "addon_b";
    cc_v4_v5.addons_updated[0].old_version.toString.should == "17.0.1.0.0";
    cc_v4_v5.addons_updated[0].new_version.toString.should == "17.0.1.0.1";

    // checkVersions — no changes since v5 (worktree is at v5): ok, no errors, has_changes=false
    auto res_no_changes = repo.checkVersions(OdooSerie("17.0"), rev_v5);
    res_no_changes.ok.shouldBeTrue;
    res_no_changes.has_changes.shouldBeFalse;
    res_no_changes.errors.length.should == 0;

    // checkVersions — changes v1..v2: addon_a bumped (pass), addon_b not bumped (fail)
    auto res_v1_v2 = repo.checkVersions(OdooSerie("17.0"), rev_v1, rev_v2);
    res_v1_v2.has_changes.shouldBeTrue;
    res_v1_v2.ok.shouldBeFalse;     // addon_b has same version
    res_v1_v2.errors.length.should == 1;
    res_v1_v2.errors[0].addon_name.should == "addon_b";
    res_v1_v2.errors[0].messages.length.should == 1;

    // checkVersions — bump addon_b version and commit; now both pass
    repo_path.join("addon_a", "__manifest__.py").writeFile(
        `{"name": "addon_a", "version": "17.0.1.2.0", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_a", "__manifest__.py"));
    repo.commit("Bump addon_a version");
    auto rev_v6 = repo.getCurrCommit();

    auto res_v5_v6 = repo.checkVersions(OdooSerie("17.0"), rev_v5, rev_v6);
    res_v5_v6.has_changes.shouldBeTrue;
    res_v5_v6.ok.shouldBeTrue;
    res_v5_v6.errors.length.should == 0;

    // checkVersions — wrong serie fails
    auto res_wrong_serie = repo.checkVersions(OdooSerie("16.0"), rev_v1, rev_v2);
    res_wrong_serie.ok.shouldBeFalse;
    res_wrong_serie.errors.length.should == 2;  // both addons fail serie check, one entry per addon

    // checkVersions — OdooSerie.init skips serie check; both addons bumped v1→v5
    auto res_no_serie = repo.checkVersions(OdooSerie.init, rev_v1, rev_v5);
    res_no_serie.ok.shouldBeTrue;
    res_no_serie.errors.length.should == 0;

    // checkVersions — addon with wrong serie AND version not bumped gets two messages
    repo_path.join("addons", "addon_b", "__manifest__.py").writeFile(
        `{"name": "addon_b", "version": "15.0.1.0.1", "depends": ["base"]}`);
    repo.add(repo_path.join("addons", "addon_b", "__manifest__.py"));
    repo.commit("Set addon_b to wrong serie and low version");
    auto rev_v7 = repo.getCurrCommit();

    auto res_multi = repo.checkVersions(OdooSerie("17.0"), rev_v6, rev_v7);
    res_multi.ok.shouldBeFalse;
    res_multi.errors.length.should == 1;          // one addon failed
    res_multi.errors[0].addon_name.should == "addon_b";
    res_multi.errors[0].messages.length.should == 2;  // serie mismatch + version not bumped both reported

    // checkVersions — changes object is exposed on result
    auto res_with_changes = repo.checkVersions(OdooSerie("17.0"), rev_v1, rev_v2);
    res_with_changes.changes.shouldNotBeNull;
    res_with_changes.changes.addons_updated.length.should == 2;

    // collectChanges — addon keyed by directory name, not manifest 'name' field
    // Set manifest name to something different from the directory name
    repo_path.join("addon_a", "__manifest__.py").writeFile(
        `{"name": "My Addon A (Display Name)", "version": "17.0.1.3.0", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_a", "__manifest__.py"));
    repo.commit("Set addon_a display name differs from dir name");
    auto rev_v8 = repo.getCurrCommit();

    auto cc_dir_name = repo.collectChanges(rev_v7, rev_v8);
    cc_dir_name.addons_updated.length.should == 1;
    cc_dir_name.addons_updated[0].name.should == "addon_a";  // directory name, not "My Addon A (Display Name)"

    // collectChanges — tolerates a non-standard start version (e.g. a plain
    // "1.0.0" without a serie prefix, common in third-party addons). The
    // start version's semver drives the changelog range filter, and semver
    // carries an `in (isStandard)` contract; collectChanges must skip the
    // filter for such addons rather than asserting/crashing.
    repo_path.join("addon_a", "__manifest__.py").writeFile(
        `{"name": "addon_a", "version": "1.0.0", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_a", "__manifest__.py"));
    repo.commit("Set addon_a to a non-standard version");
    auto rev_v9 = repo.getCurrCommit();

    repo_path.join("addon_a", "__manifest__.py").writeFile(
        `{"name": "addon_a", "version": "1.1.0", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_a", "__manifest__.py"));
    repo.commit("Bump addon_a non-standard version");
    auto rev_v10 = repo.getCurrCommit();

    auto cc_nonstd = repo.collectChanges(rev_v9, rev_v10);  // must not throw
    cc_nonstd.addons_updated.length.should == 1;
    cc_nonstd.addons_updated[0].name.should == "addon_a";
    cc_nonstd.addons_updated[0].old_version.toString.should == "1.0.0";
    cc_nonstd.addons_updated[0].new_version.toString.should == "1.1.0";
    // Changelogs are unsupported for non-standard versions: the changelog is
    // skipped rather than read, so no notable-changes entry is recorded.
    cc_nonstd.notable_changes.length.should == 0;
}


// ensureChangelog + readAddonChangelog — worktree and historical end refs.
unittest {
    import std.algorithm: canFind, map;
    import std.array: array;
    import unit_threaded.assertions;
    import thepath: createTempPath;

    auto root = createTempPath;
    scope(exit) root.remove();

    auto repo = new AddonRepository(GitRepository.initialize(root.join("repo")));
    auto repo_path = repo.path;

    // Two addons at 17.0.1.0.0
    foreach(name; ["addon_a", "addon_b"]) {
        repo_path.join(name).mkdir(false);
        repo_path.join(name, "__init__.py").writeFile("");
        repo_path.join(name, "__manifest__.py").writeFile(
            `{"name": "%s", "version": "17.0.1.0.0", "depends": ["base"]}`.format(name));
    }
    repo.add(repo_path.join("addon_a"));
    repo.add(repo_path.join("addon_b"));
    repo.commit("Initial commit");
    auto rev0 = repo.getCurrCommit();

    // Worktree: bump both addons; only addon_a gets a changelog entry.
    foreach(name; ["addon_a", "addon_b"])
        repo_path.join(name, "__manifest__.py").writeFile(
            `{"name": "%s", "version": "17.0.1.1.0", "depends": ["base"]}`.format(name));
    repo_path.join("addon_a", "changelog").mkdir(false);
    repo_path.join("addon_a", "changelog", "changelog.1.1.0.md").writeFile(
        "Added feature X.");

    // ── worktree end_ref ──

    // 'all': addon_b lacks a changelog → fail, addon_b reported.
    auto wt_all = repo.ensureChangelog(rev0);
    wt_all.has_changes.shouldBeTrue;
    wt_all.ok.shouldBeFalse;
    wt_all.addons_missing_changelog.should == ["addon_b"];

    // 'any': addon_a has a changelog → pass.
    repo.ensureChangelog(
        rev0, GIT_REF_WORKTREE, ChangelogRequirement.any).ok.shouldBeTrue;

    // Add a changelog for addon_b too → 'all' now passes.
    repo_path.join("addon_b", "changelog").mkdir(false);
    repo_path.join("addon_b", "changelog", "changelog.1.1.0.md").writeFile(
        "Fixed bug Y.");
    repo.ensureChangelog(rev0).ok.shouldBeTrue;

    // readAddonChangelog — worktree reads the entry just written.
    auto wt_cl = repo.readAddonChangelog(Path("addon_a"), GIT_REF_WORKTREE);
    wt_cl.length.should == 1;
    wt_cl[0].ver.toString.should == "1.1.0";

    // ── historical end_ref (proves changelog is read from the ref) ──

    repo.add(repo_path.join("addon_a"));
    repo.add(repo_path.join("addon_b"));
    repo.commit("Bump both addons with changelogs");
    auto rev1 = repo.getCurrCommit();

    // Both addons carry a changelog at rev1 → 'all' passes comparing two refs.
    auto ref_all = repo.ensureChangelog(rev0, rev1);
    ref_all.has_changes.shouldBeTrue;
    ref_all.ok.shouldBeTrue;
    ref_all.addons_missing_changelog.length.should == 0;

    // readAddonChangelog from the historical ref finds the committed entry...
    auto ref_cl = repo.readAddonChangelog(Path("addon_a"), rev1);
    ref_cl.length.should == 1;
    ref_cl[0].ver.toString.should == "1.1.0";

    // ...and is read from the ref, not the worktree: delete it on disk, the
    // ref-based read is unaffected and the ref-to-ref check still passes.
    repo_path.join("addon_a", "changelog", "changelog.1.1.0.md").remove();
    repo.readAddonChangelog(Path("addon_a"), rev1).length.should == 1;
    repo.ensureChangelog(rev0, rev1).ok.shouldBeTrue;

    // No changes between identical refs → ok, nothing to require.
    auto none = repo.ensureChangelog(rev1, rev1);
    none.has_changes.shouldBeFalse;
    none.ok.shouldBeTrue;

    // Added-only diff is exempt: a brand-new addon needs no changelog.
    repo_path.join("addon_c").mkdir(false);
    repo_path.join("addon_c", "__init__.py").writeFile("");
    repo_path.join("addon_c", "__manifest__.py").writeFile(
        `{"name": "addon_c", "version": "17.0.1.0.0", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_c"));
    repo.commit("Add addon_c (no changelog)");
    auto rev2 = repo.getCurrCommit();

    auto added = repo.ensureChangelog(rev1, rev2);
    added.has_changes.shouldBeTrue;
    added.changes.addons_added.length.should == 1;
    added.changes.addons_updated.length.should == 0;
    added.ok.shouldBeTrue;  // added addon exempt under 'all'
    // 'any' with no updated addons → nothing to require → pass.
    repo.ensureChangelog(
        rev1, rev2, ChangelogRequirement.any).ok.shouldBeTrue;
}


unittest {
    import std.algorithm: canFind;
    import std.string: strip;
    import unit_threaded.assertions;
    import thepath: createTempPath;
    import versioned: VersionPart;
    import odood.exception: OdoodException;
    import odood.utils.odoo.serie: OdooSerie;
    import odood.utils.odoo.std_version: OdooStdVersion;

    auto root = createTempPath;
    scope(exit) root.remove();

    auto repo = new AddonRepository(GitRepository.initialize(root.join("repo")));
    auto repo_path = repo.path;

    // One addon at 17.0.1.0.0
    repo_path.join("addon_a").mkdir(false);
    repo_path.join("addon_a", "__manifest__.py").writeFile(
        `{"name": "addon_a", "version": "17.0.1.0.0", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_a"));
    repo.commit("Initial commit");

    // ── initialRelease ──

    // Success: no matching tags → returns 17.0.1.0.0, nothing staged
    auto init_ver = repo.initialRelease(OdooSerie("17.0"));
    init_ver.toString.should == "17.0.1.0.0";
    repo.getChangedFiles(staged: true).length.should == 0;

    // Tag HEAD directly (no commit needed — nothing was staged)
    repo.setTag("17.0.1.0.0");

    // Reject: matching tag already exists
    try {
        repo.initialRelease(OdooSerie("17.0"));
        false.shouldBeTrue("Expected OdoodException");
    } catch (OdoodException e) {}

    // ── prepareRelease ──

    // No changes since tag → null
    repo.prepareRelease(OdooSerie("17.0")).isNull.shouldBeTrue;

    // MINOR change in addon (Y: 0→1): repo version bumped MINOR (1.0.0 → 1.1.0)
    repo_path.join("addon_a", "__manifest__.py").writeFile(
        `{"name": "addon_a", "version": "17.0.1.1.0", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_a", "__manifest__.py"));
    repo.commit("Bump addon_a to 17.0.1.1.0");

    auto res1 = repo.prepareRelease(OdooSerie("17.0"));
    res1.isNull.shouldBeFalse;
    res1.get.new_version.toString.should == "17.0.1.1.0";
    res1.get.addon_changes.shouldNotBeNull;
    res1.get.start_ref.should == "17.0.1.0.0";     // latest tag was used as start_ref
    repo.getChangedFiles(staged: true).length.should == 0;  // nothing staged by prepareRelease

    // Tag and move on to override_part test
    repo.setTag("17.0.1.1.0");

    // PATCH change in addon (Z: 0→1), but caller forces MAJOR override → 1.1.0 → 2.0.0
    repo_path.join("addon_a", "__manifest__.py").writeFile(
        `{"name": "addon_a", "version": "17.0.1.1.1", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_a", "__manifest__.py"));
    repo.commit("Patch bump addon_a to 17.0.1.1.1");

    auto res2 = repo.prepareRelease(
        serie: OdooSerie("17.0"),
        override_part: VersionPart.MAJOR.nullable);
    res2.isNull.shouldBeFalse;
    res2.get.new_version.toString.should == "17.0.2.0.0";
    res2.get.start_ref.should == "17.0.1.1.0";

    // ── getLatestPatch (chain resolution) ──

    // Build a patch chain on top of 17.0.1.1.0 (multiple tags on HEAD is fine —
    // getLatestPatch reads tag names, not commits).
    repo.setTag("17.0.1.1.1");
    repo.setTag("17.0.1.1.2");

    // Resolve from the primary (Z == 0) → latest in the 17.0.1.1.* chain.
    repo.getLatestPatch(OdooStdVersion("17.0.1.1.0"))
        .get.toString.should == "17.0.1.1.2";

    // Resolve from an existing patch member (Z > 0) → same chain, Z ignored.
    repo.getLatestPatch(OdooStdVersion("17.0.1.1.1"))
        .get.toString.should == "17.0.1.1.2";

    // A chain with no tags → null.
    repo.getLatestPatch(OdooStdVersion("17.0.9.9.0")).isNull.shouldBeTrue;
}
