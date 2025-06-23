module odood.lib.devtools.migrate;

private import std.logger: infof, warningf;
private import std.format: format;
private import std.algorithm: canFind;

private import odood.lib.project: Project;
private import odood.exception: OdoodException;
private import odood.utils.addons.addon: OdooAddon;
private import odood.lib.devtools.utils: updateManifestVersion;
private import odood.lib.addons.repository: AddonRepository;


void migrateAddonsCode(in AddonRepository repo, in string[] addon_names=[], in bool commit=false) {
    import std.process: Config;

    // Install odoo-module-migrator if needed
    if (!repo.project.venv.bin_path.join("odoo-module-migrate").exists)
        repo.project.venv.installPyPackages("git+https://github.com/OCA/odoo-module-migrator@master");

    foreach(addon; repo.addons) {
        if (addon_names.length > 0 && !addon_names.canFind(addon.name))
            // Addon is not listed in addon_names, thus skip it
            continue;

        if (addon.manifest.module_version.serie < repo.project.odoo.serie) {
            infof("Migrating module %s (%s) to serie %s", addon.name, addon.manifest.module_version, repo.project.odoo.serie);
            auto old_serie = addon.manifest.module_version.serie;
            auto cmd = repo.project.venv.runner
                .addArgs(
                    "odoo-module-migrate",
                    "--directory=%s".format(repo.path),
                    "--modules=%s".format(addon.name),
                    "--init-version-name=%s".format(addon.manifest.module_version.serie),
                    "--target-version-name=%s".format(repo.project.odoo.serie),
                    "--format-patch",
                    "--no-commit",
                ).withFlag(Config.Flags.stderrPassThrough);
            cmd.execute.ensureOk!OdoodException(true);

            // Fix addon version, by changing only serie, because odoo-module-migrator
            // sets version to <serie>.1.0.0, that breaks version relation with previos serie.
            addon.manifest_path.updateManifestVersion(addon.manifest.module_version.withSerie(repo.project.odoo.serie));

            if (commit) {
                repo.add(addon.path);
                repo.commit(
                        "[MIG] %s: %s -> %s".format(
                            addon.name,
                            addon.manifest.module_version.serie,
                            repo.project.odoo.serie)
                );
            }
            infof("Migration of module %s completed", addon.name);
        } else if (addon.manifest.module_version.serie == repo.project.odoo.serie) {
            infof(
                "Module %s (%s) already has correct serie. No migration needed.",
                addon.name, addon.manifest.module_version);
        } else {
            warningf(
                "Module %s (%s) has greater serie than project's serie. Downgrade migrations not supported!",
                addon.name, addon.manifest.module_version);
        }
    }
}
