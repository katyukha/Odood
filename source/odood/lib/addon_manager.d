module odood.lib.addon_manager;

private import std.logger;
private import std.typecons: Nullable, nullable;
private import std.array: split;
private import std.string: join;
private import std.format: format;

private import thepath: Path;

private import odood.lib.project.config: ProjectConfig;
private import odood.lib.odoo.config: readOdooConfig;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.addon;


struct AddonManager {
    private const ProjectConfig _config;
    private Nullable!(Path[]) _addons_paths;

    /// Cmd for Install, Update addons
    private enum cmdIU {
        install,
        update,
    }

    @disable this();

    this(in ProjectConfig config) {
        _config = config;
    }

    /// Get list of paths to search for addons
    @property const(Path[]) addons_paths() {
        if (_addons_paths.isNull) {
            auto odoo_conf = _config.readOdooConfig;
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

    /// Scan for all addons available in Odoo
    OdooAddon[] scan() {
        OdooAddon[] res;
        foreach(path; addons_paths)
            res ~= scan(path);
        return res;
    }

    /// Scan specified path for addons
    OdooAddon[] scan(in Path path) {
        tracef("Searching for addons in %s", path);
        if (isOdooAddon(path)) {
            return [OdooAddon(path)];
        }

        OdooAddon[] res;

        foreach(addon_path; path.walkBreadth) {
            if (addon_path.isInside(path.join("setup")))
                // Skip modules defined in OCA setup folder to avoid duplication.
                continue;
            if (addon_path.isOdooAddon)
                res ~= OdooAddon(addon_path);
        }
        return res;
    }

    /// Link single odoo addon
    void link(in OdooAddon addon) {
        auto const dest = _config.addons_dir.join(addon.name);
        if (!dest.exists) {
            tracef("linking addon %s (%s -> %s)",
                   addon.name, addon.path, dest);
            addon.path.symlink(_config.addons_dir.join(addon.name));
        }
        if (dest.join("requirements.txt").exists) {
            infof("Installing python requirements for addon '%s'",
                  addon.name);
            _config.venv.installPyRequirements(dest.join("requirements.txt"));
        }
    }

    /// Link all addons inside specified directories
    void link(in Path search_path) {
        if (search_path.isOdooAddon)
            link(OdooAddon(search_path));
            
        foreach(addon; scan(search_path))
            link(addon);
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
            _config.odoo_serie <= OdooSerie(10) ? "--no-xmlrpc" : "--no-http",
            "--pidfile=/dev/null",
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

        _config.server.runE(server_opts);

    }

    /// Update odoo addons
    void update(in string[] addon_names, in string database) {
        if (!addon_names) {
            warning("No addons specified for 'update'.");
            return;
        }
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

}
