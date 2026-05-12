module odood.lib.addons.repository;

private import std.logger: warningf, infof;
private import std.algorithm: canFind, map, filter, maxElement;
private import std.format: format;
private import std.typecons: Nullable, nullable;
private import std.exception: enforce;
private import std.array: appender, array;
private import std.string: strip, join;

private import versioned: Version, VersionPart;
private import thepath: Path;

private import odood.utils.addons.addon: OdooAddon, findAddons;
private import odood.utils.addons.addon_changelog: OdooAddonChangelogEntry;
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

/// Addon identity at a specific git ref: path relative to repo root, name, version.
private struct AddonInfo {
    Path path;
    string name;
    OdooStdVersion addon_version;
}



// TODO: Do we need this class?
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
                    parsed.get.name,
                    parsed.get.module_version).nullable;
            // Manifest file found but unparseable — stop.
            return Nullable!AddonInfo.init;
        }
        return Nullable!AddonInfo.init;
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
                    "Addon '%s' found at two paths in end ref '%s': %s and %s. "
                    ~ "A repository must not contain duplicate addon names.".format(
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
                // Changelog files live on the filesystem, so only read them
                // when end_ref is the worktree (not a historical commit).
                OdooAddonChangelogEntry[] changelog;
                if (end_ref == GIT_REF_WORKTREE) {
                    auto addon = new OdooAddon(this.path.join(end_info.path));
                    changelog = addon.readChangelogEntries(
                        start_ver: cast(Nullable!Version)
                            start_info.addon_version.semver.nullable);
                }
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
        string[] all_tags = listLocalTags();
        if (hasRemoteUrl("origin")) {
            try {
                all_tags ~= listRemoteTags("origin");
            } catch (Exception e) {
                warningf("Cannot list remote tags (using local only): %s", e.msg);
            }
        }

        auto existing = all_tags
            .map!(t => OdooStdVersion(t))
            .filter!(v => v.isStandard && v.serie == serie)
            .array;

        enforce!OdoodException(
            existing.length == 0,
            ("Repository already has release tags for serie %s (latest: %s). "
            ~ "Use 'odood repo release' for subsequent releases.").format(
                serie, existing.maxElement));

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
      *
      * Returns: null if no changed addons detected; the new version otherwise.
      **/
    Nullable!OdooStdVersion prepareRelease(
            in OdooSerie serie,
            in Nullable!VersionPart override_part = Nullable!VersionPart.init,
            in bool ignore_translations = true) const {
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

        // Bootstrap: no prior tags — compare against origin branch.
        string start_ref = "origin/%s".format(serie);
        auto initial_version = OdooStdVersion(serie, 1, 0, 0);

        if (matching_versions.length > 0) {
            auto latest = matching_versions.maxElement;
            start_ref = latest.toString;
            initial_version = latest;  // tag name is the authoritative version
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
            return Nullable!OdooStdVersion.init;

        // 3. Reuse changes already collected by checkVersions; seed the repo version.
        auto changes = check.changes;
        changes.repo_version = initial_version;

        if (!override_part.isNull)
            changes.repo_version = changes.repo_version.incVersion(override_part.get);
        else
            changes.postProcess();

        return changes.repo_version.nullable;
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

    auto ver1 = repo.prepareRelease(OdooSerie("17.0"));
    ver1.isNull.shouldBeFalse;
    ver1.get.toString.should == "17.0.1.1.0";
    repo.getChangedFiles(staged: true).length.should == 0;  // nothing staged by prepareRelease

    // Tag and move on to override_part test
    repo.setTag("17.0.1.1.0");

    // PATCH change in addon (Z: 0→1), but caller forces MAJOR override → 1.1.0 → 2.0.0
    repo_path.join("addon_a", "__manifest__.py").writeFile(
        `{"name": "addon_a", "version": "17.0.1.1.1", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_a", "__manifest__.py"));
    repo.commit("Patch bump addon_a to 17.0.1.1.1");

    auto ver2 = repo.prepareRelease(
        serie: OdooSerie("17.0"),
        override_part: VersionPart.MAJOR.nullable);
    ver2.isNull.shouldBeFalse;
    ver2.get.toString.should == "17.0.2.0.0";
}
