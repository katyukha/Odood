module odood.lib.addons.repository;

private import std.logger: warningf, infof;
private import std.algorithm: canFind, map;
private import std.format: format;
private import std.typecons: Nullable, nullable;
private import std.exception: enforce;

private import thepath: Path;

private import odood.utils.addons.addon: OdooAddon, findAddons;
private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.addons.addon_manifest: tryParseOdooManifest;
private import odood.exception: OdoodException;
private import odood.git: GitRepository, GIT_REF_WORKTREE;


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
}

