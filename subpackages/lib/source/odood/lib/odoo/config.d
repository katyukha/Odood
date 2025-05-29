module odood.lib.odoo.config;

private import std.algorithm;
private import std.uni;
private import std.typecons;
private import std.array: join, array;

private import thepath: Path;
private import dini;

private import odood.lib.project: Project;
private import odood.utils.odoo.serie: OdooSerie;


/** Get list of system addons paths.
  *
  * List paths where Odoo system (out-of-the-box) addons located.
  **/
Path[] getSystemAddonsPaths(in Project project) {
    Path[] addons_paths = [project.odoo.path.join("addons")];
    if (project.odoo.serie <= OdooSerie(9)) {
        addons_paths ~= project.odoo.path.join("openerp", "addons");
    } else {
        addons_paths ~= project.odoo.path.join("odoo", "addons");
    }
    return addons_paths;
}

/** Initialize default odoo config
  *
  * Params:
  *     project = Odoo project instance
  *
  * Returns:
  *    Ini file structure, that could be used to read and modify config
  **/
Ini initOdooConfig(in Project project) {
    // Generate default config
    Ini odoo_conf;
    IniSection options = IniSection("options");
    odoo_conf.addSection(options);

    string[] addons_path = project.getSystemAddonsPaths.map!((p) => p.toString).array.dup;
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


/** We have to preprocess config value to handle
  * possible False and None values.
  * And this function will do this job.
  **/
string getConfVal(Ini config, in string key, return in string defValue=null) {
    string value = config["options"].getKey(key, "None");
    if (value.toLower.among("none", "false"))
        return defValue;
    return value;
}


/** Parse Odoo's database config and return tuple with following fields:
  * host, port, user, password
  **/
auto parseOdooDatabaseConfig(in Project project) {
    // TODO: handle test config
    auto config = project.readOdooConfig;


    return Tuple!(
        string, "host", string, "port", string, "user", string, "password"
    )(
        config.getConfVal("db_host"),
        config.getConfVal("db_port"),
        config.getConfVal("db_user"),
        config.getConfVal("db_password"),
    );
}
