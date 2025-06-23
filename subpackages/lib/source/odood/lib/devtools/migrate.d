module odood.lib.devtools.migrate;

private import std.logger: infof, warningf;
private import std.format: format;

private import odood.lib.project: Project;
private import odood.exception: OdoodException;
private import odood.utils.addons.addon: OdooAddon;


void migrateAddonsCode(in Project project, in OdooAddon[] addons) {
    import std.process: Config;

    // Install odoo-module-migrator if needed
    if (!project.venv.bin_path.join("odoo-module-migrate").exists)
        project.venv.installPyPackages("git+https://github.com/OCA/odoo-module-migrator@master");

    foreach(addon; addons) {
        if (addon.manifest.module_version.serie < project.odoo.serie) {
            infof("Migrating module %s (%s) to serie %s", addon.name, addon.manifest.module_version, project.odoo.serie);
            project.venv.runner
                .addArgs(
                    "odoo-module-migrate",
                    "--directory=%s".format(addon.path.realPath.parent),
                    "--modules=%s".format(addon.name),
                    "--init-version-name=%s".format(addon.manifest.module_version.serie),
                    "--target-version-name=%s".format(project.odoo.serie),
                    "--format-patch",
                ).withFlag(Config.Flags.stderrPassThrough)
                .execute.ensureOk!OdoodException(true);
            infof("Migration of module %s completed", addon.name);
        } else if (addon.manifest.module_version.serie == project.odoo.serie) {
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
