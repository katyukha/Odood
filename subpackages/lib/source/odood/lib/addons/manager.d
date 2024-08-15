module odood.lib.addons.manager;

private import std.logger;
private import std.typecons: Nullable, nullable;
private import std.array: split, empty, array;
private import std.string: join, strip, startsWith, toLower;
private import std.format: format;
private import std.file: SpanMode;
private import std.exception: enforce, ErrnoException;
private import std.algorithm: map, canFind;

private import thepath: Path, createTempPath;
private import zipper: Zipper;

private import odood.lib.project: Project;
private import odood.lib.odoo.config: readOdooConfig;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.addons.addon;
private import odood.utils.addons.odoo_requirements:
    parseOdooRequirements, OdooRequirementsLineType;
private import odood.lib.addons.repository: AddonRepository;
private import odood.utils: download;
private import odood.utils.git: parseGitURL, gitClone;
private import odood.exception: OdoodException;

/// Install python dependencies requirements.txt by default
immutable bool DEFAULT_INSTALL_PY_REQUREMENTS = true;

/// Install python dependencies from addon manifest by default
immutable bool DEFAULT_INSTALL_MANIFEST_REQUREMENTS = false;


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

    this(in Project project, in bool test_mode=false) {
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
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUREMENTS) const {
        // TODO: Implement separate struct LinkOptions to handle all link options.
        //       this could simplify the code.
        auto dest = _project.directories.addons.join(addon.name);
        if (!dest.exists) {
            tracef("Linking addon %s (%s -> %s)",
                   addon.name, addon.path, dest);
            addon.path.symlink(_project.directories.addons.join(addon.name));
        } else if (force) {
            tracef(
                ("Removing allready existing addon %s at %s " ~
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

        if (py_requirements && dest.join("requirements.txt").exists) {
            // Prefere installation from requirements.txt inside addon
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
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUREMENTS) const {
        foreach(addon; scan(search_path, recursive))
            link(addon, force, py_requirements, manifest_requirements);

        if (py_requirements && search_path.join("requirements.txt").exists) {
            infof("Installing python requirements from '%s'",
                  search_path.join("requirements.txt"));
            _project.venv.installPyRequirements(
                search_path.join("requirements.txt"));
        }
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
        auto db = _project.dbSQL(database);
        scope(exit) db.close();

        return db.isAddonInstalled(addon);
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

        string[] server_opts=[
            "-d", database,
            "--max-cron-threads=0",
            "--stop-after-init",
            _project.odoo.serie <= OdooSerie(10) ? "--no-xmlrpc" : "--no-http",
            "--pidfile=",  // We must not write to pidfile to avoid conflicts with running Odoo
            "--logfile=%s".format(_project.odoo.logfile.toString),
        ];

        if (!_project.hasDatabaseDemoData(database))
            server_opts ~= ["--without-demo=all"];

        auto addon_names_csv = addon_names.join(",");
        final switch(cmd) {
            case cmdIU.install:
                infof("Installing addons (db=%s): %s", database, addon_names_csv);
                _project.server(_test_mode).runE(
                    server_opts ~ ["--init=%s".format(addon_names_csv)], env);
                infof("Installation of addons for database %s completed!", database);
                break;
            case cmdIU.update:
                infof("Updating addons (db=%s): %s", database, addon_names_csv);
                _project.server(_test_mode).runE(
                    server_opts ~ ["--update=%s".format(addon_names_csv)], env);
                infof("Update of addons for database %s completed!", database);
                break;
            case cmdIU.uninstall:
                infof("Uninstalling addons (db=%s): %s", database, addon_names_csv);
                _project.lodoo(_test_mode).addonsUninstall(
                    database,
                    addon_names);
                infof("Uninstallation of addons for database %s completed!", database);
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
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUREMENTS) const {
        auto temp_dir = createTempPath();
        scope(exit) temp_dir.remove();

        auto download_path = temp_dir.join("%s.zip".format(addon_name));
        infof("Downloading addon %s from odoo apps...", addon_name);
        download(
            "https://apps.odoo.com/loempia/download/%s/%s/%s.zip?deps".format(
                addon_name, _project.odoo.serie, addon_name),
            download_path);
        infof("Unpacking addon %s from odoo apps...", addon_name);
        Zipper(download_path.toAbsolute).extractTo(temp_dir.join("apps"));


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
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUREMENTS) {
        foreach(line; parseOdooRequirements(path))
            // TODO: In case when only single module requested,
            //       add only single module
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
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUREMENTS) {

        auto git_url = parseGitURL(url);
        auto dest = _project.directories.repositories.join(
                git_url.toPathSegments.map!((p) => p.toLower).array);

        if (dest.exists) {
            warningf(
                "Repository %s seems to be already cloned to %s. Skipping...",
                url, dest);
            return;
        }

        gitClone(git_url, dest, branch, single_branch);

        // TODO: Do we need to create instance of repo here?
        auto repo = new AddonRepository(_project, dest);
        link(
            repo.path,
            true,  // recursive
            false, // force
            py_requirements,
            manifest_requirements);

        // If there is odoo_requirements.txt file present, then we have to
        // process it.
        if (recursive && repo.path.join("odoo_requirements.txt").exists) {
            processOdooRequirements(
                repo.path.join("odoo_requirements.txt"),
                single_branch,
                recursive,
                py_requirements,
                manifest_requirements);
        }
    }

    /// ditto
    void addRepo(
            in string url,
            in bool single_branch=false,
            in bool recursive=true,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUREMENTS) {
        addRepo(
            url,
            _project.odoo.serie.toString,
            single_branch,
            recursive,
            py_requirements,
            manifest_requirements);
    }

    /// Get repository instance for specified path
    auto getRepo(in Path path) {
        enforce!OdoodException(
            path.join(".git").exists,
            "Is not a git root directory.");
        return new AddonRepository(_project, path);
    }
}
