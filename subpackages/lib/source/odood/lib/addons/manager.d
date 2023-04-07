module odood.lib.addons.manager;

private import std.logger;
private import std.typecons: Nullable, nullable;
private import std.array: split, empty, array;
private import std.string: join;
private import std.format: format;
private import std.file: SpanMode;
private import std.exception: enforce;
private import std.algorithm: map;

private import thepath: Path, createTempPath;

private import odood.lib.project: Project;
private import odood.lib.odoo.config: readOdooConfig;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.addons.addon;
private import odood.lib.addons.odoo_requirements:
    parseOdooRequirements, OdooRequirementsLineType;
private import odood.lib.addons.repository: AddonRepository;
private import odood.lib.utils: download;
private import odood.lib.zip: extract_zip_archive;
private import odood.lib.exception: OdoodException;


/// Struct that provide API to manage odoo addons for the project
struct AddonManager {
    private const Project _project;
    private Nullable!(Path[]) _addons_paths;

    /// Cmd for Install, Update addons
    private enum cmdIU {
        install,
        update,
        uninstall,
    }

    @disable this();

    this(in Project project) {
        _project = project;
    }

    /// Get list of paths to search for addons
    @property const(Path[]) addons_paths() {
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
                return new OdooAddon(path.join(addon_name), addon_name).nullable;
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

    /// Scan for all addons available in Odoo
    OdooAddon[] scan() {
        OdooAddon[] res;
        foreach(path; addons_paths)
            res ~= scan(path);
        return res;
    }

    /// Scan specified path for addons
    OdooAddon[] scan(in Path path, in bool recursive=false) const {
        tracef("Searching for addons in %s", path);
        if (isOdooAddon(path)) {
            return [new OdooAddon(path)];
        }

        OdooAddon[] res;

        auto walk_mode = recursive ? SpanMode.breadth : SpanMode.shallow;
        foreach(addon_path; path.walk(walk_mode)) {
            if (addon_path.isInside(path.join("setup")))
                // Skip modules defined in OCA setup folder to avoid duplication.
                continue;
            if (addon_path.isOdooAddon)
                res ~= new OdooAddon(addon_path);
        }
        return res;
    }

    /// Link single odoo addon
    void link(in OdooAddon addon, in bool force=false) const {
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

        if (dest.join("requirements.txt").exists) {
            infof("Installing python requirements for addon '%s'",
                  addon.name);
            _project.venv.installPyRequirements(dest.join("requirements.txt"));
        }
    }

    /// Link all addons inside specified directories
    void link(
            in Path search_path,
            in bool recursive=false,
            in bool force=false) const {
        if (search_path.isOdooAddon)
            link(new OdooAddon(search_path), force);
            
        foreach(addon; scan(search_path, recursive))
            link(addon, force);
    }

    /// Check if addon is linked or not
    bool isLinked(in ref OdooAddon addon) const {
        import std.exception: ErrnoException;
        auto check_path = _project.directories.addons.join(addon.name);
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
            in string[string] env) const {

        string[] server_opts=[
            "-d", database,
            "--max-cron-threads=0",
            "--stop-after-init",
            _project.odoo.serie <= OdooSerie(10) ? "--no-xmlrpc" : "--no-http",
            "--pidfile=/dev/null",
            "--logfile=%s".format(_project.odoo.logfile.toString),
        ];

        if (!_project.hasDatabaseDemoData(database))
            server_opts ~= ["--without-demo=all"];

        auto addon_names_csv = addon_names.join(",");
        final switch(cmd) {
            case cmdIU.install:
                infof("Installing addons (db=%s): %s", database, addon_names_csv);
                _project.server.runE(
                    server_opts ~ ["--init=%s".format(addon_names_csv)], env);
                infof("Installation of addons for database %s completed!", database);
                break;
            case cmdIU.update:
                infof("Updating addons (db=%s): %s", database, addon_names_csv);
                _project.server.runE(
                    server_opts ~ ["--update=%s".format(addon_names_csv)], env);
                infof("Update of addons for database %s completed!", database);
                break;
            case cmdIU.uninstall:
                infof("Uninstalling addons (db=%s): %s", database, addon_names_csv);
                _project.lodoo.addonsUninstall(
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
        update(database, addons.map!((a) => getByName(a).get).array);
    }

    /// ditto
    void update(
            in string database,
            in string[] addons,
            in string[string] env) {
        update(database, addons.map!((a) => getByName(a).get).array, env);
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
        install(database, addons.map!((a) => getByName(a).get).array);
    }

    /// ditto
    void install(
            in string database,
            in string[] addons,
            in string[string] env) {
        install(database, addons.map!((a) => getByName(a).get).array, env);
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
        uninstall(database, addons.map!((a) => getByName(a).get).array);
    }

    /// ditto
    void uninstall(
            in string database,
            in string[] addons,
            in string[string] env) {
        uninstall(database, addons.map!((a) => getByName(a).get).array, env);
    }

    /// ditto
    void uninstall(
            in string database,
            in Path search_path,
            in string[string] env=null) {
        uninstall(database, scan(search_path), env);
    }

    /// Download from odoo apps
    void downloadFromOdooApps(in string addon_name) const {
        auto temp_dir = createTempPath();
        scope(exit) temp_dir.remove();

        auto download_path = temp_dir.join("%s.zip".format(addon_name));
        infof("Downloading addon %s from odoo apps...", addon_name);
        download(
            "https://apps.odoo.com/loempia/download/%s/%s/%s.zip?deps".format(
                addon_name, _project.odoo.serie, addon_name),
            download_path);
        infof("Unpacking addon %s from odoo apps...", addon_name);
        extract_zip_archive(download_path, temp_dir.join("apps"));

        enforce!OdoodException(
            isOdooAddon(temp_dir.join("apps", addon_name)),
            "Downloaded archive does not contain requested odoo app!");

        foreach(addon; scan(temp_dir.join("apps"))) {
            if (_project.directories.addons.join(addon.name).exists) {
                warningf("Cannot copy module %s. it is already present. Skipping.", addon.name);
            } else {
                infof("Copying addon %s...", addon.name);
                addon.path.copyTo(_project.directories.downloads);
                link(_project.directories.downloads.join(addon.name));
            }
        }
    }

    /// Process odoo_requirements.txt file, that is used by odoo-helper
    void processOdooRequirements(in Path path, in bool single_branch=false) {
        foreach(line; parseOdooRequirements(path))
            final switch (line.type) {
                case OdooRequirementsLineType.repo:
                    addRepo(
                        line.repo_url,
                        line.branch.empty ?
                            _project.odoo.serie.toString : line.branch,
                        single_branch);
                    break;
                case OdooRequirementsLineType.odoo_apps:
                    downloadFromOdooApps(line.addon);
                    break;
            }
    }

    /// Add new addon repository to project
    void addRepo(
            in string url, in string branch, in bool single_branch=false) {
        import std.algorithm;
        import std.string: toLower;
        import std.array: array;
        import odood.lib.git: parseGitURL, gitClone;

        auto git_url = parseGitURL(url);
        auto dest = _project.directories.repositories.join(
                git_url.toPathSegments.map!((p) => p.toLower).array);

        // TODO: Add recursion protection
        if (dest.exists) {
            warningf(
                "Repository %s seems to be already cloned to %s. Skipping...",
                url, dest);
            return;
        }

        gitClone(git_url, dest, branch, single_branch);

        // TODO: Do we need to create instance of repo here?
        auto repo = new AddonRepository(_project, dest);
        link(repo.path, true);

        // If there is odoo_requirements.txt file present, then we have to
        // process it.
        if (repo.path.join("odoo_requirements.txt").exists) {
            processOdooRequirements(
                repo.path.join("odoo_requirements.txt"),
                single_branch);
        }
    }

    /// ditto
    void addRepo(in string url, in bool single_branch=false) {
        addRepo(url, _project.odoo.serie.toString, single_branch);
    }

    /// Get repository instance for specified path
    auto getRepo(in Path path) {
        enforce!OdoodException(
            path.join(".git").exists,
            "Is not a git root directory.");
        return new AddonRepository(_project, path);
    }
}
