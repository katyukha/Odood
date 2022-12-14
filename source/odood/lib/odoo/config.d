module odood.lib.odoo.config;

private import thepath: Path;
private import dini;

private import odood.lib.project.config: ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;


/** Initialize default odoo config
  **/
Ini initOdooConfig(in ProjectConfig config) {
    import std.array;
    // Generate default config
    Ini odoo_conf;
    IniSection options = IniSection("options");
    odoo_conf.addSection(options);

    string[] addons_path =[config.odoo_path.join("addons").toString];
    if (config.odoo_serie <= OdooSerie(9)) {
        addons_path ~= config.odoo_path.join("openerp").toString;
    } else {
        addons_path ~= config.odoo_path.join("odoo").toString;
    }
    addons_path ~= config.addons_dir.toString;

    odoo_conf["options"].setKey("addons_path", join(addons_path, ","));
    odoo_conf["options"].setKey("data_dir", config.data_dir.toString);
    odoo_conf["options"].setKey("logfile", config.log_file.toString);
    odoo_conf["options"].setKey("admin_passwd", "admin");
    return odoo_conf;
}
