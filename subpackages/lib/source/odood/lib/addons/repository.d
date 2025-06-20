module odood.lib.addons.repository;

private import std.logger: warningf, infof;
private import std.algorithm: canFind, map;
private import std.format: format;
private import std.typecons: Nullable, nullable;
private import std.exception: enforce;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.utils.addons.addon: OdooAddon;
private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.addons.addon_manifest: tryParseOdooManifest;
private import odood.exception: OdoodException;
private import odood.git: GitRepository, GIT_REF_WORKTREE;


// TODO: Do we need this class?
class AddonRepository : GitRepository{
    private const Project _project;

    @disable this();

    this(in Project project, in Path path) {
        super(path);
        _project = project;
    }

    this(in Project project, in GitRepository repo) {
        super(repo.path);
        _project = project;
    }

    /** Return Odood project associated with this addons repository
      **/
    auto project() const => _project;

    /** Scan repository for addons and return array of odoo addons,
      * found in this repo.
      * This method searches for addons recursively by default.
      *
      * Params:
      *     recursive = If set to true, search for addons recursively inside repo.
      *         Otherwise, scan only the root directory of the repo for addons.
      **/
    auto addons(in bool recursive=true) const {
        return project.addons.scan(path, recursive);
    }

    /** Get version of addon in specified commit
      *
      * Params:
      *     addon = Addon to get version for
      *     rev = git revision to get addon version for
      **/
    Nullable!OdooStdVersion getAddonVersion(in OdooAddon addon, in string rev) {
        enforce!OdoodException(
            addon.path.isInside(this.path),
            "Addon must be inside repo");
        auto g_path = addon.path.relativeTo(this.path);
        auto g_manifest_path = g_path.join("__manifest__.py");
        if (!this.isFileExists(g_manifest_path, rev))
            g_manifest_path = g_path.join("__openerp__.py");
        if (!this.isFileExists(g_manifest_path, rev))
            // File not exists in spefied revision
            return Nullable!OdooStdVersion.init;

        auto manifest = tryParseOdooManifest(this.getContent(g_manifest_path, rev));
        if (manifest.isNull)
            // Cannot read manifest in spefied revision
            return Nullable!OdooStdVersion.init;

        return manifest.get.module_version.nullable;
    }
    /** Get changed addons.
        Thus method mostly used by dev utils to automate some tasks
        interacting with git.
      **/
    auto getChangedModules(in string start_ref, in string end_ref, in bool ignore_translations=true) const {
        Path[] changedAddonPaths;
        foreach(path; getChangedFiles(start_ref, end_ref, ignore_translations ? [":(exclude)*.po", ":(exclude)*.pot"] : [])) {
           auto manifest_path = path.searchFileUp("__manifest__.py");
           if (manifest_path.isNull)
               manifest_path = path.searchFileUp("__openerp__.py");
           if (manifest_path.isNull)
               continue;

           if (!changedAddonPaths.canFind(manifest_path.get.parent))
               changedAddonPaths ~= [manifest_path.get.parent];
        }
        return changedAddonPaths.map!((p) => new OdooAddon(p));
    }

    /// ditto
    auto getChangedModules(in bool ignore_translations=true) const {
        return getChangedModules(
            start_ref: "origin/%s".format(_project.odoo.serie),
            end_ref: GIT_REF_WORKTREE,
            ignore_translations: ignore_translations);
    }
}
