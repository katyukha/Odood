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
        addons_path ~= project.odoo.path.join("openerp", "addons").toString;
    } else {
        addons_path ~= project.odoo.path.join("odoo", "addons").toString;
    }
    addons_path ~= project.directories.addons.toString;

    odoo_conf["options"].setKey("addons_path", join(addons_path, ","));
    odoo_conf["options"].setKey("data_dir", project.directories.data.toString);
    odoo_conf["options"].setKey("logfile", project.odoo.logfile.toString);
    odoo_conf["options"].setKey("admin_passwd", "admin");

    if (project.odoo.serie < 8)
        // Disable logrotate for Odoo version 7.0, because it seems to be buggy
        odoo_conf["options"].setKey("logrotate", "False");

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


/** Odoo config builder - struct that helps to build complex odoo configs
  **/
struct OdooConfigBuilder {
    private Ini _odoo_conf;
    private const Project _project;

    @disable this();

    this(in Project project) {
        _project = project;
        _odoo_conf = _project.initOdooConfig;
    }

    /** Set configuration for database connection
      **/
    ref typeof(this) setDBConfig(
            in string db_host,
            in string db_port,
            in string db_user,
            in string db_password) {
        _odoo_conf["options"].setKey("db_host", db_host);
        _odoo_conf["options"].setKey("db_port", db_port);
        _odoo_conf["options"].setKey("db_user", db_user);
        _odoo_conf["options"].setKey("db_password", db_password);
        return this;
    }

    /** Set Http configuration
      **/
    ref typeof(this) setHttp(in string host, in string port) {
        if (_project.odoo.serie < 11) {
            _odoo_conf["options"].setKey("xmlrpc_interface", host);
            _odoo_conf["options"].setKey("xmlrpc_port", port);
        } else {
            _odoo_conf["options"].setKey("http_interface", host);
            _odoo_conf["options"].setKey("http_port", port);
        }
        return this;
    }

    /** Return resulting odoo configuration (Ini)
      **/
    auto result() {
        return _odoo_conf;
    }
}
