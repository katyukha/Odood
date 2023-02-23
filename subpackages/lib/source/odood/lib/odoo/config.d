module odood.lib.odoo.config;

private import thepath: Path;
private import dini;

private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;


/** Initialize default odoo config
  *
  * Params:
  *     project = Odoo project instance
  *
  * Returns:
  *    Ini file structure, that could be used to read and modify config
  **/
Ini initOdooConfig(in Project project) {
    import std.array;
    // Generate default config
    Ini odoo_conf;
    IniSection options = IniSection("options");
    odoo_conf.addSection(options);

    string[] addons_path =[project.odoo.path.join("addons").toString];
    if (project.odoo.serie <= OdooSerie(9)) {
        addons_path ~= project.odoo.path.join("openerp").toString;
    } else {
        addons_path ~= project.odoo.path.join("odoo").toString;
    }
    addons_path ~= project.directories.addons.toString;

    odoo_conf["options"].setKey("addons_path", join(addons_path, ","));
    odoo_conf["options"].setKey("data_dir", project.directories.data.toString);
    odoo_conf["options"].setKey("logfile", project.odoo.logfile.toString);
    odoo_conf["options"].setKey("admin_passwd", "admin");
    return odoo_conf;
}


/** Read odoo config from specified file.
  *
  * Params:
  *     odoo_conf_path = Path to configuration to read
  *
  * Returns:
  *    Ini file structure, that could be used to read and modify config
  **/
Ini readOdooConfig(in Path odoo_conf_path) {
    return Ini.Parse(odoo_conf_path.toString);
}


/** Read odoo default Odoo configuration
  *
  * Params:
  *     project = Odood Project instance
  *
  * Returns:
  *    Ini file structure, that could be used to read and modify config
  **/
Ini readOdooConfig(in Project project) {
    return readOdooConfig(project.odoo.configfile);
}
