module odood.lib.addon_manager;

private import std.logger;

private import thepath: Path;

private import odood.lib.project.config: ProjectConfig;
private import odood.lib.odoo.addon;


struct AddonManager {
    private const ProjectConfig _config;

    @disable this();

    this(in ProjectConfig config) {
        _config = config;
    }

    /// Scan specified path for addons
    OdooAddon[] scan(in Path path) {
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
        if (search_path.isOdooAddon) {
            link(OdooAddon(search_path));
        }
            
        foreach(addon; scan(search_path)) {
            link(addon);
        }
    }

}
