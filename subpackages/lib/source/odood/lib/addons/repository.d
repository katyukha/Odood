module odood.lib.addons.repository;

private import std.logger: warningf, infof;
private import std.algorithm: canFind, map;
private import std.format: format;
private import std.typecons: Nullable, nullable;
private import std.exception: enforce;
private import std.array: appender;

private import thepath: Path;

private import odood.utils.addons.addon: OdooAddon, findAddons;
private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.addons.addon_manifest: tryParseOdooManifest;
private import odood.exception: OdoodException;
private import odood.git: GitRepository, GIT_REF_WORKTREE;


struct AddonCheckError {
    string addon_name;
    string[] messages;
}

/** Result of a version-check run across changed addons in a repository. **/
struct AddonVersionCheckResult {
    bool ok = true;           /// true if all changed addons passed all checks
    bool has_changes;         /// true if at least one changed addon was found
    AddonCheckError[] errors; /// one entry per failing addon, possibly with multiple messages

    void addError(in string addon_name, in string message) {
        ok = false;
        foreach(ref e; errors)
            if (e.addon_name == addon_name) { e.messages ~= message; return; }
        errors ~= AddonCheckError(addon_name, [message]);
    }
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

        foreach(addon; getChangedModules(start_ref, end_ref, ignore_translations)) {
            result.has_changes = true;

            auto maybe_start_version = getAddonVersion(addon, start_ref);
            if (maybe_start_version.isNull)
                continue;  // new addon — no prior version to compare

            auto maybe_end_version = getAddonVersion(addon, end_ref);
            if (maybe_end_version.isNull)
                continue;  // addon removed — nothing to check

            auto start_version = maybe_start_version.get;
            auto end_version   = maybe_end_version.get;

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

    // checkVersions — no changes since v2: ok, no errors, has_changes=false
    auto res_no_changes = repo.checkVersions(OdooSerie("17.0"), rev_v2);
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
    repo_path.join("addon_b", "__manifest__.py").writeFile(
        `{"name": "addon_b", "version": "17.0.1.0.1", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_b", "__manifest__.py"));
    repo.commit("Bump addon_b version");
    auto rev_v3 = repo.getCurrCommit();

    auto res_v1_v3 = repo.checkVersions(OdooSerie("17.0"), rev_v1, rev_v3);
    res_v1_v3.has_changes.shouldBeTrue;
    res_v1_v3.ok.shouldBeTrue;
    res_v1_v3.errors.length.should == 0;

    // checkVersions — wrong serie fails
    auto res_wrong_serie = repo.checkVersions(OdooSerie("16.0"), rev_v1, rev_v3);
    res_wrong_serie.ok.shouldBeFalse;
    res_wrong_serie.errors.length.should == 2;  // both addons fail serie check, one entry per addon

    // checkVersions — OdooSerie.init skips serie check
    auto res_no_serie = repo.checkVersions(OdooSerie.init, rev_v1, rev_v3);
    res_no_serie.ok.shouldBeTrue;
    res_no_serie.errors.length.should == 0;

    // checkVersions — addon with wrong serie AND version not bumped gets two messages
    repo_path.join("addon_b", "__manifest__.py").writeFile(
        `{"name": "addon_b", "version": "15.0.1.0.1", "depends": ["base"]}`);
    repo.add(repo_path.join("addon_b", "__manifest__.py"));
    repo.commit("Set addon_b to wrong serie and low version");
    auto rev_v4 = repo.getCurrCommit();

    auto res_multi = repo.checkVersions(OdooSerie("17.0"), rev_v3, rev_v4);
    res_multi.ok.shouldBeFalse;
    res_multi.errors.length.should == 1;          // one addon failed
    res_multi.errors[0].addon_name.should == "addon_b";
    res_multi.errors[0].messages.length.should == 2;  // serie mismatch + version not bumped both reported
}

