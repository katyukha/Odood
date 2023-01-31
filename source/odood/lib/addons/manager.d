module odood.lib.addons.manager;

private import std.logger;
private import std.typecons: Nullable, nullable;
private import std.array: split, empty;
private import std.string: join;
private import std.format: format;
private import std.file: SpanMode;
private import std.exception: enforce;

private import thepath: Path, createTempPath;

private import odood.lib.project: Project;
private import odood.lib.odoo.config: readOdooConfig;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.addon;
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

    Nullable!OdooAddon getByName(in string addon_name) {
        foreach(path; addons_paths) {
            if (path.join(addon_name).isOdooAddon)
                return new OdooAddon(path.join(addon_name), addon_name).nullable;
        }
        return Nullable!OdooAddon.init;
    }

    /// Scan for all addons available in Odoo
    OdooAddon[] scan(in bool recursive=false) {
        OdooAddon[] res;
        foreach(path; addons_paths)
            res ~= scan(path, recursive);
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
        auto const dest = _project.directories.addons.join(addon.name);
        if (!dest.exists) {
            tracef("linking addon %s (%s -> %s)",
                   addon.name, addon.path, dest);
            addon.path.symlink(_project.directories.addons.join(addon.name));
        } else if (force) {
            tracef(
                ("Removing allready existing addon %s at %s " ~
                 "before linking from %s").format(
                     addon.name, dest, addon.path));
            dest.remove();
            tracef("linking addon %s (%s -> %s)",
                   addon.name, addon.path, dest);
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
        auto check_path = _project.directories.addons.join(addon.name);
        if (check_path.exists &&
                check_path.isSymlink &&
                check_path.readLink().toAbsolute == addon.path.toAbsolute)
            return true;
        return false;
    }

    /// Initial method, that can do install 
    private void _run_install_update_addons(
            in string[] addon_names,
            in string database,
            in cmdIU cmd) {

        string[] server_opts=[
            "-d", database,
            "--max-cron-threads=0",
            "--stop-after-init",
            _project.odoo.serie <= OdooSerie(10) ? "--no-xmlrpc" : "--no-http",
            "--pidfile=/dev/null",
            "--logfile=%s".format(_project.odoo.logfile.toString),
        ];

        final switch(cmd) {
            case cmdIU.install:
                server_opts ~= ["--init=%s".format(addon_names.join(","))];
                break;
            case cmdIU.update:
                server_opts ~= ["--update=%s".format(addon_names.join(","))];
                break;
        }


        /* TODO: Handle demo data
            if ! odoo_db_is_demo_enabled -q "$db"; then
                odoo_options+=( "--without-demo=all" );
            fi
        */

        _project.server.runE(server_opts);

    }

    /// Update odoo addons
    void update(in string[] addon_names, in string database) {
        if (!addon_names) {
            warning("No addons specified for 'update'.");
            return;
        }
        infof(
            "Updating modules %s into database %s...",
            addon_names.join(", "), database);
        _run_install_update_addons(addon_names, database, cmdIU.update);
    }

    /// ditto
    void update(in OdooAddon[] addons, in string database) {
        string[] addon_names;
        foreach(addon; addons)
            addon_names ~= addon.name;
        update(addon_names, database);
    }
    /// ditto
    void update(in Path search_path, in string database) {
        update(scan(search_path), database);
    }

    /// install odoo addons
    void install(in string[] addon_names, in string database) {
        if (!addon_names) {
            warning("No addons specified for 'update'.");
            return;
        }
        infof(
            "Installing modules %s into database %s...",
            addon_names.join(", "), database);
        _run_install_update_addons(addon_names, database, cmdIU.install);
    }

    /// ditto
    void install(in OdooAddon[] addons, in string database) {
        string[] addon_names;
        foreach(addon; addons)
            addon_names ~= addon.name;
        install(addon_names, database);
    }
    /// ditto
    void install(in Path search_path, in string database) {
        install(scan(search_path), database);
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
                warningf("Cannot copy module %s. it is already present. Skipping.", addon_name);
            } else {
                infof("Copying addon %s...", addon.name);
                addon.path.copyTo(_project.directories.downloads);
                link(_project.directories.downloads.join(addon.name));
            }
        }
    }

    /// Process odoo_requirements.txt file, that is used by odoo-helper
    void processOdooRequirements(in Path path) {
        foreach(line; parseOdooRequirements(path)) {
            if (line.type == OdooRequirementsLineType.repo) {
                addRepo(
                    line.repo_url,
                    line.branch.empty ?
                        _project.odoo.serie.toString : line.branch);
            }
        }
    }

    /// Add new addon repo to project
    void addRepo(in string url, in string branch) {
        import odood.lib.git: parseGitURL, gitClone;

        auto git_url = parseGitURL(url);
        auto dest = _project.directories.repositories.join(
                git_url.toPathSegments);

        // TODO: Add recursion protection
        if (dest.exists) {
            warningf(
                "Repository %s seems to be already cloned to %s. Skipping...",
                url, dest);
            return;
        }

        gitClone(git_url, dest, branch);

        // TODO: Do we need to create instance of repo here?
        auto repo = AddonRepository(_project, dest);
        link(repo.path, true);

        // If there is odoo_requirements.txt file present, then we have to
        // process it.
        if (repo.path.join("odoo_requirements.txt").exists) {
            processOdooRequirements(repo.path.join("odoo_requirements.txt"));
        }
    }

    /// Get repository instance for specified path
    auto getRepo(in Path path) {
        enforce!OdoodException(
            path.join(".git").exists,
            "Is not a git root directory.");
        return AddonRepository(_project, path);
    }
}
