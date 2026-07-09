module odood.project.addons.manager;

private import std.logger;
private import std.typecons: Nullable, nullable;
private import std.array: split, empty, array;
private import std.string: join, strip, startsWith, toLower;
private import std.format: format;
private import std.file: SpanMode;
private import std.exception: enforce, ErrnoException, basicExceptionCtors;
private import std.algorithm: map, canFind;

private import thepath: Path, createTempPath;
private import darkarchive: DarkArchiveReader, DarkArchiveFormat;

private import odood.project: Project;
private import odood.lib.python.venv: PyRequirements;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.addons.addon;
private import odood.utils.addons.odoo_requirements:
    parseOdooRequirements, OdooRequirementsLineType;
private import odood.utils: download;
private import odood.exception: OdoodException;

/// Install python dependencies requirements.txt by default
immutable bool DEFAULT_INSTALL_PY_REQUIREMENTS = true;

/// Install python dependencies from addon manifest by default
immutable bool DEFAULT_INSTALL_MANIFEST_REQUIREMENTS = false;

class AddonsInstallUpdateException: OdoodException {
    mixin basicExceptionCtors;
}

class AddonsInstallException : AddonsInstallUpdateException {
    mixin basicExceptionCtors;
}

class AddonsUpdateException : AddonsInstallUpdateException {
    mixin basicExceptionCtors;
}

// TODO: Think, may be it have sense to keep OCA modules database in the code,
//       to be able to automatically resolve dependencies.


/// Classification of where an addon's code lives.
enum AddonLocationSource {
    absent,       /// not found anywhere
    odooCore,     /// ships with Odoo (system addons path)
    customRepo,   /// lives in a repository under repositories/
    downloads,    /// downloaded from Odoo Apps (downloads/)
    other,        /// found in some other addons_path
}


/// Stable string key for an addon location source (for JSON / tooling output).
string toKey(in AddonLocationSource source) pure nothrow @safe {
    final switch(source) {
        case AddonLocationSource.absent:     return "absent";
        case AddonLocationSource.odooCore:   return "odoo-core";
        case AddonLocationSource.customRepo: return "custom-repo";
        case AddonLocationSource.downloads:  return "downloads";
        case AddonLocationSource.other:      return "other";
    }
}


/// Result of locating an addon by name.
struct AddonLocation {
    /// Requested addon name
    string name;

    /// Whether the addon was found anywhere
    bool found;

    /// Where the addon's code lives
    AddonLocationSource source = AddonLocationSource.absent;

    /// Real (symlink-resolved) path to the addon code, if found
    Nullable!Path path;

    /// Owning repository root (set only for customRepo)
    Nullable!Path repo;

    /// Whether the addon is linked into custom_addons (visible to Odoo)
    bool is_linked;

    /// Manifest 'installable' flag (only meaningful when found)
    bool is_installable;
}


/// Struct that provide API to manage odoo addons for the project
struct AddonManager {
    private const Project _project;
    private const bool _test_mode;
    private Nullable!(Path[]) _addons_paths;

    /// Cmd for Install, Update addons
    private enum cmdIU {
        install,
        update,
        uninstall,
    }

    @disable this();

    this(in Project project, in bool test_mode=false) pure {
        _project = project;
        _test_mode = test_mode;
    }

    /// Get list of paths to search for addons
    const(Path[]) addons_paths() {
        if (_addons_paths.isNull) {
            auto odoo_conf = _project.readOdooConfig;
            auto search_paths = odoo_conf["options"].getKey("addons_path");

            Path[] res;
            foreach(apath; search_paths.split(",")) {
                auto p = Path(apath);
                if (p.exists)
                    res ~= p;
            }
            _addons_paths = res.nullable;
        }
        return _addons_paths.get;
    }

    /// Get list of system addons paths (with addons that come with Odoo out-of-the-box)
    Path[] system_addons_paths() const {
        return _project.getSystemAddonsPaths;
    }

    /** Get addon instance by its name
      *
      * Params:
      *    addon_name = Name of addon to check
      * Returns:
      *    Nullable instance of addon
      **/
    Nullable!OdooAddon getByName(in string addon_name) {
        foreach(path; addons_paths) {
            if (path.join(addon_name).isOdooAddon)
                return new OdooAddon(path.join(addon_name)).nullable;
        }
        return Nullable!OdooAddon.init;
    }

    /** Get addon instance by its path
      *
      * Params:
      *    addon_path = path to addon
      * Returns:
      *    Nullable instance of addon
      **/
    Nullable!OdooAddon getByPath(in Path addon_path) {
        if (addon_path.isOdooAddon)
            return new OdooAddon(addon_path).nullable;
        return Nullable!OdooAddon.init;
    }

    /** Check if it is addon path, then check if it is 
      * odoo addon. If provided value is not path or it does not point to addon
      * then assume that it is name of addon, and try to find addon by name.
      **/
    Nullable!OdooAddon getByString(in string addon_name) {
        auto addon = getByPath(Path(addon_name));
        if (!addon.isNull)
            return addon;
        return getByName(addon_name);
    }

    /** Get list of all system addons available in this Odoo instance
      **/
    OdooAddon[] getSystemAddonsList() const {
        OdooAddon[] result;
        foreach(apath; system_addons_paths) {
            result ~= scan(apath);
        }
        return result;
    }

    /** Locate an addon by name and classify where its code lives.
      *
      * Answers "where is addon X, and is it available at all?" — used by
      * `odood addons where` and by tooling. Resolves the custom_addons symlink
      * to the real code path, and classifies the source as Odoo core, a
      * repository under repositories/, an Odoo Apps download, or absent.
      *
      * Params:
      *     name = technical name of the addon to locate
      * Returns:
      *     AddonLocation describing where (and whether) the addon was found.
      **/
    AddonLocation locate(in string name) {
        AddonLocation result;
        result.name = name;

        // Resolve the real code path, and whether it is linked into custom_addons.
        Nullable!Path real_path;

        auto link_path = _project.directories.addons.join(name);
        if (link_path.isOdooAddon) {
            result.is_linked = true;
            real_path = link_path.realPath.nullable;
        } else {
            // Not linked — look for the real code in repositories/, then
            // downloads/, then the Odoo core addons paths.
            if (_project.directories.repositories.exists)
                foreach(addon; scan(_project.directories.repositories, true))
                    if (addon.name == name) {
                        real_path = addon.path.realPath.nullable;
                        break;
                    }
            if (real_path.isNull) {
                auto dl = _project.directories.downloads.join(name);
                if (dl.isOdooAddon)
                    real_path = dl.realPath.nullable;
            }
            if (real_path.isNull)
                foreach(apath; system_addons_paths)
                    if (apath.join(name).isOdooAddon) {
                        real_path = apath.join(name).realPath.nullable;
                        break;
                    }
        }

        if (real_path.isNull) {
            result.source = AddonLocationSource.absent;
            return result;
        }

        result.found = true;
        result.path = real_path;
        result.is_installable = (new OdooAddon(real_path.get)).manifest.installable;

        result.source = classifySource(real_path.get);
        if (result.source == AddonLocationSource.customRepo)
            result.repo = addonRepo(real_path.get);

        return result;
    }

    /** Classify where an addon path lives: Odoo core, a repository under
      * repositories/, an Odoo Apps download, or some other addons path.
      *
      * Cheap — pure path containment, no scanning. The path is resolved to its
      * real location first, so a custom_addons symlink classifies by its target.
      **/
    AddonLocationSource classifySource(in Path addon_path) const {
        auto rp = addon_path.realPath;
        if (_project.directories.repositories.exists &&
                rp.isInside(_project.directories.repositories.realPath))
            return AddonLocationSource.customRepo;
        if (_project.directories.downloads.exists &&
                rp.isInside(_project.directories.downloads.realPath))
            return AddonLocationSource.downloads;
        if (system_addons_paths.canFind!(p => p.exists && rp.isInside(p.realPath)))
            return AddonLocationSource.odooCore;
        return AddonLocationSource.other;
    }

    /** Owning repository root for an addon path, if it lives in a git
      * repository under repositories/. Null otherwise.
      **/
    Nullable!Path addonRepo(in Path addon_path) const {
        import odood.git: isGitRepo, getGitTopLevel;
        auto rp = addon_path.realPath;
        if (!(_project.directories.repositories.exists &&
                rp.isInside(_project.directories.repositories.realPath)))
            return Nullable!Path.init;
        if (rp.isGitRepo)
            return getGitTopLevel(rp).nullable;
        return Nullable!Path.init;
    }

    /** Parse file that contains list of addons
      *
      * Format of addons list file is following:
      * ----------------------------------------
      * addon1
      * # comment
      * addon2
      * ----------------------------------------
      * 
      * Params:
      *     path = path to addons list file
      * Return:
      *     Array of addon instances
      **/
    OdooAddon[] parseAddonsList(in Path path) {
        auto file = path.openFile;
        scope(exit) file.close();

        OdooAddon[] result;
        foreach(string addon_name; file.byLineCopy) {
            if (!addon_name.strip)
                continue;
            if (addon_name.strip.startsWith("#"))
                continue;
            auto addon = getByString(addon_name.strip);
            enforce!OdoodException(
                !addon.isNull,
                "%s does not look like addon name or path to addon".format(
                    addon_name));
            if (!result.canFind(addon.get))
                result ~= addon.get;
        }
        return result;
    }

    /// Scan for all addons available in Odoo
    OdooAddon[] scan() {
        OdooAddon[] res;
        foreach(path; addons_paths)
            res ~= scan(path);
        return res;
    }

    /** Scan specified path for addons
      *
      * Params:
      *     path = path to addon or directory that contains addons
      *     recursive = if set to true, then search for addons in subdirectories
      *
      * Returns:
      *     Array of OdooAddons found in specified path.
      **/
    OdooAddon[] scan(in Path path, in bool recursive=false) const {
        tracef("Searching for addons in %s", path);
        return findAddons(path, recursive);
    }

    /** Link all addons inside specified directories
      *
      * Params:
      *     addon = Instance of OdooAddon to link.
      *     force = if set, then rewrite link to this addon
      *         (if it was already linked).
      *     py_requirements = if set, then automatically install python
      *         requirements for requirements.txt file
      *     manifest_requirements = if set, then automatically install
      *         python requirements from manifest
      **/
    void link(
            OdooAddon addon,
            in bool force=false,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS,
            in bool install_requirements=true) const {
        // TODO: Implement separate struct LinkOptions to handle all link options.
        //       this could simplify the code.
        auto dest = _project.directories.addons.join(addon.name);
        if (dest.toAbsolute == addon.path.toAbsolute) {
            tracef("Addon %s already in custom addons dir... There is no need to link it.", addon.name);
        } else if (!dest.exists) {
            tracef("Linking addon %s (%s -> %s)",
                   addon.name, addon.path, dest);
            addon.path.symlink(_project.directories.addons.join(addon.name));
        } else if (force) {
            tracef(
                ("Removing already existing addon %s at %s " ~
                 "before linking from %s"),
                addon.name, dest, addon.path);
            dest.remove();
            tracef(
                "Linking addon %s (%s -> %s)", addon.name, addon.path, dest);
            addon.path.symlink(_project.directories.addons.join(addon.name));
        } else if (dest.exists && dest.isSymlink && !dest.readLink.exists) {
            tracef("Removing broken symlink at %s ...", dest);
            dest.remove();
            tracef(
                "Linking addon %s (%s -> %s)", addon.name, addon.path, dest);
            addon.path.symlink(_project.directories.addons.join(addon.name));
        } else if (dest.exists && dest.isSymlink && !dest.readLink.isOdooAddon) {
            tracef("Removing symlink %s to directory that is not odoo addon ...", dest);
            dest.remove();
            tracef(
                "Linking addon %s (%s -> %s)", addon.name, addon.path, dest);
            addon.path.symlink(_project.directories.addons.join(addon.name));
        }

        if (install_requirements) {
            if (py_requirements && dest.join("requirements.txt").exists) {
                // Prefer installation from requirements.txt inside addon
                // and if no requirements.txt found, then try to install from manifest.
                infof("Installing python requirements for addon '%s'",
                      addon.name);
                _project.venv.installPyRequirements(dest.join("requirements.txt"));
            } else if (manifest_requirements && addon.manifest.python_dependencies.length > 0) {
                infof("Installing python requirements for addon '%s' from manifest",
                      addon.name);
                _project.venv.installPyPackages(addon.manifest.python_dependencies);
            }
        }
    }

    /** Link all addons inside specified directories
      *
      * Params:
      *     search_path = path to search for addons in.
      *         Could be path to single addon.
      *     recursive = if set to true, the search for addons recursively,
      *         otherwise, search for addons only directly in specified path.
      *     force = if set, then rewrite link to this addon
      *         (if it was already linked).
      *     py_requirements = if set, then automatically install python
      *         requirements for requirements.txt file
      *     manifest_requirements = if set, then automatically install
      *         python requirements from manifest
      **/
    void link(
            in Path search_path,
            in bool recursive=false,
            in bool force=false,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS,
            in bool individual_requirements=false,
            in bool with_odoo_requirements=false) const {
        if (individual_requirements) {
            // Old behavior: install requirements per-addon individually
            foreach(addon; scan(search_path, recursive))
                link(addon, force, py_requirements, manifest_requirements, true);

            if (py_requirements && search_path.join("requirements.txt").exists) {
                infof("Installing python requirements from '%s'",
                      search_path.join("requirements.txt"));
                _project.venv.installPyRequirements(
                    search_path.join("requirements.txt"));
            }
        } else {
            // New behavior: symlink only, then batch install all requirements
            foreach(addon; scan(search_path, recursive))
                link(addon, force, py_requirements, manifest_requirements, false);

            if (py_requirements || manifest_requirements) {
                auto reqs = collectPyRequirements(
                    search_path, recursive, py_requirements, manifest_requirements);

                if (with_odoo_requirements
                        && _project.odoo.path.join("requirements.txt").exists) {
                    reqs.addRequirementsFile(
                        _project.odoo.path.join("requirements.txt"));
                }

                if (!reqs.empty) {
                    infof("Installing python requirements (batched)");
                    _project.venv.installBatchPyRequirements(reqs);
                }
            }
        }
    }

    /** Collect Python requirements from addons in the given path without installing.
      *
      * Scans addons and gathers their requirements.txt file paths and
      * manifest python_dependencies into a PyRequirements struct for
      * batch installation.
      *
      * Params:
      *     search_path = path to search for addons in.
      *         Could be path to single addon.
      *     recursive = if set to true, search for addons recursively.
      *     py_requirements = collect from requirements.txt files
      *     manifest_requirements = collect from manifest python_dependencies
      *
      * Returns:
      *     PyRequirements struct with all gathered requirements
      **/
    PyRequirements collectPyRequirements(
            in Path search_path,
            in bool recursive=false,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS) const {
        PyRequirements reqs;

        foreach (addon; scan(search_path, recursive)) {
            auto dest = _project.directories.addons.join(addon.name);
            auto check_path = (dest.exists && dest.isSymlink) ? dest : addon.path;

            if (py_requirements && check_path.join("requirements.txt").exists) {
                reqs.addRequirementsFile(check_path.join("requirements.txt"));
            } else if (manifest_requirements && addon.manifest.python_dependencies.length > 0) {
                reqs.addPackages(addon.manifest.python_dependencies);
            }
        }

        // Directory-level requirements.txt
        if (py_requirements && search_path.join("requirements.txt").exists) {
            reqs.addRequirementsFile(search_path.join("requirements.txt"));
        }

        return reqs;
    }

    /// Check if addon is linked or not
    bool isLinked(in OdooAddon addon) const {
        const auto check_path = _project.directories.addons.join(addon.name);
        if (!check_path.exists)
            return false;

        // Try to get realpath to check for. If there is broken symlink,
        // then error will be raised
        Path check_real_path;
        try {
            check_real_path = check_path.realPath;
        } catch (ErrnoException e) {
            return false;
        }

        // In check if check_path points to same directory as addon's path
        if (check_real_path == addon.path.realPath)
            return true;
        return false;
    }

    /** Check if specified addon is installed in specified db
      *
      * Params:
      *     database = name of database to check if addon is installed
      *     addon = name of addon to check if it is installed
      **/
    bool isInstalled(in string database, in string addon) {
        return _project.dbSQL(database).isAddonInstalled(addon);
    }

    /// ditto
    bool isInstalled(in string database, in OdooAddon addon) {
        return isInstalled(database, addon.name);
    }

    /** Install or update odoo adodns from specified database
      *
      * Params:
      *     addon_names = list of names of addons to install or update
      *     database = name of database to run operation for
      *     cmd = Command that describes what to do: install or update
      *     env = Extra environment variables to provide for the Odoo
      *           if needed. Used by openupgrade.
      **/
    private void _run_install_update_addons(
            in string database,
            in string[] addon_names,
            in cmdIU cmd,
            in string[string] env=null) const {
        import std.datetime.stopwatch;

        // Initialize server runner configuration
        auto runner = _project.server.getServerRunner(
            "-d", database,
            "--max-cron-threads=0",
            "--stop-after-init",
            _project.odoo.serie <= OdooSerie(10) ? "--no-xmlrpc" : "--no-http",
            "--pidfile=",  // We must not write to pidfile to avoid conflicts with running Odoo
        ).withEnv(env);
        if (!_project.odoo.logfile.isNull)
            runner.addArgs("--logfile=%s".format(_project.odoo.logfile.get.toString));
        if (!_project.dbSQL(database).hasDemoData)
            runner.addArgs("--without-demo=all");

        auto addon_names_csv = addon_names.join(",");
        auto sw = StopWatch(AutoStart.yes);
        final switch(cmd) {
            case cmdIU.install:
                infof("Installing addons (db=%s): %s", database, addon_names_csv);
                auto install_runner = runner.withArgs("--init=%s".format(addon_names_csv));
                // In no-logfile mode Odoo logs to stderr; pass it through so the
                // caller (e.g. a container) can see the output.
                if (_project.odoo.logfile.isNull)
                    install_runner.setStderrPassThrough;
                install_runner.execute.ensureOk!AddonsInstallException(true);
                infof(
                    "Installation of addons for database %s completed in %s!",
                    database, sw.peek);
                break;
            case cmdIU.update:
                infof("Updating addons (db=%s): %s", database, addon_names_csv);
                auto update_runner = runner.withArgs("--update=%s".format(addon_names_csv));
                // In no-logfile mode Odoo logs to stderr; pass it through so the
                // caller (e.g. a container) can see the output.
                if (_project.odoo.logfile.isNull)
                    update_runner.setStderrPassThrough;
                update_runner.execute.ensureOk!AddonsUpdateException(true);
                infof(
                    "Update of addons for database %s completed in %s!",
                    database, sw.peek);
                break;
            case cmdIU.uninstall:
                infof("Uninstalling addons (db=%s): %s", database, addon_names_csv);
                _project.lodoo(_test_mode).addonsUninstall(
                    database,
                    addon_names);
                infof(
                    "Uninstallation of addons for database %s completed in %s!",
                    database, sw.peek);
                break;
        }
    }

    /** Update odoo addons
      *
      * Params:
      *     addons = list of addons (or names of addons) to update
      *     database = name of database to update addons in
      *     env = additional environment variables to be used during update
      *     search_path = path to search addons to update
      **/
    void update(
            in string database,
            in OdooAddon[] addons,
            in string[string] env=null) const {
        if (!addons) {
            warning("No addons specified for 'update'.");
            return;
        }
        _run_install_update_addons(
            database, addons.map!(a => a.name).array, cmdIU.update, env);
    }

    /// ditto
    void update(
            in string database,
            in string[] addons...) {
        _run_install_update_addons(
            database, addons, cmdIU.update);
    }

    /// ditto
    void update(
            in string database,
            in string[] addons,
            in string[string] env) {
        _run_install_update_addons(
            database, addons, cmdIU.update, env);
    }

    /// ditto
    void update(
            in string database,
            in Path search_path,
            in string[string] env=null) const {
        update(database, scan(search_path), env);
    }

    /// Update all odoo addons for specific database
    void updateAll(in string database, in string[string] env=null) const {
        _run_install_update_addons(database, ["all"], cmdIU.update, env);
    }

    /** Install odoo addons
      *
      * Params:
      *     addons = list of addons (or names of addons) to install
      *     database = name of database to install addons in
      *     env = additional environment variables to be used during install
      *     search_path = path to search addons to install
      **/
    void install(
            in string database,
            in OdooAddon[] addons,
            in string[string] env=null) {
        if (!addons) {
            warning("No addons specified for 'install'.");
            return;
        }
        _run_install_update_addons(
            database, addons.map!(a => a.name).array, cmdIU.install, env);
    }

    /// ditto
    void install(
            in string database,
            in string[] addons...) {
        _run_install_update_addons(database, addons, cmdIU.install);
    }

    /// ditto
    void install(
            in string database,
            in string[] addons,
            in string[string] env) {
        _run_install_update_addons(database, addons, cmdIU.install, env);
    }

    /// ditto
    void install(
            in string database,
            in Path search_path,
            in string[string] env=null) {
        install(database, scan(search_path), env);
    }

    /** Unnstall odoo addons
      *
      * Params:
      *     addons = list of addons (or names of addons) to uninstall
      *     database = name of database to uninstall addons in
      *     env = additional environment variables to be used during uninstall
      *     search_path = path to search addons to uninstall
      **/
    void uninstall(
            in string database,
            in OdooAddon[] addons,
            in string[string] env=null) {
        _run_install_update_addons(
            database,
            addons.map!(a => a.name).array,
            cmdIU.uninstall,
            env);
    }

    /// ditto
    void uninstall(
            in string database,
            in string[] addons...) {
        _run_install_update_addons(database, addons, cmdIU.uninstall);
    }

    /// ditto
    void uninstall(
            in string database,
            in string[] addons,
            in string[string] env) {
        _run_install_update_addons(database, addons, cmdIU.uninstall, env);
    }

    /// ditto
    void uninstall(
            in string database,
            in Path search_path,
            in string[string] env=null) {
        uninstall(database, scan(search_path), env);
    }

    /// Download from odoo apps
    void downloadFromOdooApps(
            in string addon_name,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS) const {
        auto temp_dir = createTempPath();
        scope(exit) temp_dir.remove();

        auto download_path = temp_dir.join("%s.zip".format(addon_name));
        infof("Downloading addon %s from odoo apps...", addon_name);
        download(
            "https://apps.odoo.com/loempia/download/%s/%s/%s.zip?deps".format(
                addon_name, _project.odoo.serie, addon_name),
            download_path);
        infof("Unpacking addon %s from odoo apps...", addon_name);
        DarkArchiveReader!(DarkArchiveFormat.zip)(download_path.toAbsolute).extractTo(temp_dir.join("apps"));


        enforce!OdoodException(
            isOdooAddon(temp_dir.join("apps", addon_name)),
            "Downloaded archive does not contain requested odoo app!");

        foreach(addon; scan(temp_dir.join("apps"))) {
            if (_project.directories.addons.join(addon.name).exists) {
                warningf("Cannot copy module %s. it is already present. Skipping.", addon.name);
            } else {
                infof("Copying addon %s...", addon.name);
                addon.path.copyTo(_project.directories.downloads);
                link(
                    _project.directories.downloads.join(addon.name),
                    false,  // force
                    py_requirements,
                    manifest_requirements);
            }
        }
    }

    /** Process odoo_requirements.txt file, that is used by odoo-helper
      * Can process lines that specify repository to clone or name of module
      * that have to be downloaded from Odoo Apps
      *
      * In case if recursive is set to false, then only specified
      * odoo_requirements.txt file will be processed.
      * In case if recursive is set to true, then system will search
      * for odoo_requirements.txt file in root of each clonned repo
      * and thus will try to recursively clone repo dependencies.
      *
      * Params:
      *     path = path of odoo_requirements.txt file to process
      *     single_branch = clone only single branch of repositories specified
      *         by path
      *     recurisve = recursively process odoo_requirements.txt in
      *         clonned repositories
      *     py_requirements = if set, then automatically install python
      *         requirements for requirements.txt file
      *     manifest_requirements = if set, then automatically install
      *         python requirements from manifest
      **/
    void processOdooRequirements(
            in Path path,
            in bool single_branch=false,
            in bool recursive=false,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS) {
        auto req_path = path.exists && path.isDir ? path.join("odoo_requirements.txt") : path;
        enforce!OdoodException(
            req_path.exists,
            "odoo_requirements.txt not found: %s".format(req_path));
        foreach(line; parseOdooRequirements(req_path))
            // `-m/--module` on repo lines (line.addon) is intentionally
            // ignored: documented as a no-op kept for backward compatibility
            // with odoo-helper-scripts — the whole repository is added.
            // If single-module fetch is ever implemented, update
            // docs/odood/src/odoo-requirements-txt.md accordingly.
            final switch (line.type) {
                case OdooRequirementsLineType.repo:
                    addRepo(
                        line.repo_url,
                        line.branch.empty ?
                            _project.odoo.serie.toString : line.branch,
                        single_branch,
                        recursive);
                    break;
                case OdooRequirementsLineType.odoo_apps:
                    downloadFromOdooApps(line.addon, py_requirements, manifest_requirements);
                    break;
            }
    }

    /** Add new addon repository to project, and optionally
      * clone repository dependencies, specified in odoo_requirements.txt file
      *
      * If branch is not specified, the serie branch will be clonned.
      *
      * Params:
      *     url = repository url to clone from
      *     branch = repository branch to clone
      *     single_branch = if set, then clone only single branch of repo
      *     recursive = if set, then automatically process odoo_requirements.txt
      *         inside clonned repo, to recursively fetch its dependencies
      *     py_requirements = if set, then automatically install python
      *         requirements for requirements.txt file
      *     manifest_requirements = if set, then automatically install
      *         python requirements from manifest
      **/
    void addRepo(
            in string url,
            in string branch,
            in bool single_branch=false,
            in bool recursive=true,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS) {
        _project.repositories(_test_mode).add(
            url,
            branch,
            single_branch,
            recursive,
            py_requirements,
            manifest_requirements);
    }

    /// ditto
    void addRepo(
            in string url,
            in bool single_branch=false,
            in bool recursive=true,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS) {
        _project.repositories(_test_mode).add(
            url,
            single_branch,
            recursive,
            py_requirements,
            manifest_requirements);
    }

    /// Get repository instance for specified path
    auto getRepo(in Path path) {
        return _project.repositories(_test_mode).get(path);
    }
}


unittest {
    import unit_threaded.assertions;

    AddonLocationSource.absent.toKey.should == "absent";
    AddonLocationSource.odooCore.toKey.should == "odoo-core";
    AddonLocationSource.customRepo.toKey.should == "custom-repo";
    AddonLocationSource.downloads.toKey.should == "downloads";
    AddonLocationSource.other.toKey.should == "other";
}


// Test AddonManager.locate classification (no Odoo install / DB required).
unittest {
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;
    import std.file: symlink;
    import odood.utils.odoo.serie: OdooSerie;

    auto root = createTempPath;
    scope(exit) root.remove();

    auto project = new Project(root, OdooSerie(17));
    auto am = project.addons;

    void makeAddon(in Path path, in bool installable) {
        path.mkdir(true);
        path.join("__manifest__.py").writeFile(
            "{'name': '%s', 'installable': %s}".format(
                path.baseName, installable ? "True" : "False"));
    }

    // A repository addon, linked into custom_addons via a symlink.
    auto repo_addon = root.join("repositories", "acme", "myrepo", "my_addon");
    makeAddon(repo_addon, true);
    root.join("custom_addons").mkdir(true);
    symlink(
        repo_addon.toString,
        root.join("custom_addons", "my_addon").toString);

    // A repository addon that is NOT linked.
    auto repo_addon2 = root.join("repositories", "acme", "myrepo", "other_addon");
    makeAddon(repo_addon2, true);

    // A downloaded (Odoo Apps) addon, not linked, not installable.
    auto dl_addon = root.join("downloads", "dl_addon");
    makeAddon(dl_addon, false);

    // Linked repo addon → custom-repo, linked, installable.
    auto loc1 = am.locate("my_addon");
    loc1.found.shouldBeTrue;
    loc1.is_linked.shouldBeTrue;
    loc1.source.should == AddonLocationSource.customRepo;
    loc1.is_installable.shouldBeTrue;
    loc1.path.get.should == repo_addon.realPath;

    // Unlinked repo addon → custom-repo, not linked.
    auto loc2 = am.locate("other_addon");
    loc2.found.shouldBeTrue;
    loc2.is_linked.shouldBeFalse;
    loc2.source.should == AddonLocationSource.customRepo;

    // Download addon → downloads, not linked, not installable.
    auto loc3 = am.locate("dl_addon");
    loc3.found.shouldBeTrue;
    loc3.is_linked.shouldBeFalse;
    loc3.source.should == AddonLocationSource.downloads;
    loc3.is_installable.shouldBeFalse;

    // Missing addon → absent.
    auto loc4 = am.locate("nonexistent_addon");
    loc4.found.shouldBeFalse;
    loc4.source.should == AddonLocationSource.absent;
    loc4.path.isNull.shouldBeTrue;

    // classifySource works directly on a known path (no by-name search).
    am.classifySource(repo_addon).should == AddonLocationSource.customRepo;
    am.classifySource(dl_addon).should == AddonLocationSource.downloads;
}
