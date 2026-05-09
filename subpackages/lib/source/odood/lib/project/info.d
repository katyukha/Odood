module odood.lib.project.info;

private import std.format: format;
private import std.json: JSONValue;
private import std.string: split, strip, startsWith;
private import std.conv: to;

private import odood.lib.project.project: Project, OdooInstallType;
private import odood.lib.project.config: ProjectServerSupervisor;
private import odood.lib.odoo.config: parseOdooDatabaseConfig;
private import odood.lib: _version;


/** Static environment information about an Odood project.
  *
  * Holds all non-runtime info (versions, paths, config) and provides
  * formatted text and JSON output.
  **/
struct ProjectInfo {
    // Odood
    string odood_version;

    // Project
    string project_root;
    string config_path;

    // Odoo
    string odoo_serie;
    string odoo_branch;
    string odoo_repo;
    string odoo_install_type;
    string odoo_path;

    // Python / Virtualenv
    string python_version;
    string lodoo_version;
    string venv_path;

    // Database
    string db_host;
    string db_port;
    string db_user;

    // HTTP
    string http_host;
    string http_port;

    // Server management
    string server_supervisor;
    string server_user;

    // Assembly (optional)
    string assembly_path;

    /// Formatted text output with sections and aligned values
    string toString() const {
        string result;

        void section(string name) {
            if (result.length > 0)
                result ~= "\n";
            result ~= name ~ ":\n";
        }

        void field(string label, string value) {
            if (value.length > 0)
                result ~= "    %-18s%s\n".format(label ~ ":", value);
        }

        section("Odood");
        field("Version", odood_version);

        section("Project");
        field("Root", project_root);
        field("Config", config_path);

        section("Odoo");
        field("Version", odoo_serie);
        field("Branch", odoo_branch);
        field("Repository", odoo_repo);
        field("Install type", odoo_install_type);
        field("Path", odoo_path);

        section("Python");
        field("Version", python_version);
        field("LOdoo", lodoo_version);
        field("Virtualenv", venv_path);

        section("Database");
        field("Host", db_host);
        field("Port", db_port);
        field("User", db_user);

        section("HTTP");
        field("Host", http_host);
        field("Port", http_port);

        section("Server");
        field("Supervisor", server_supervisor);
        field("User", server_user);

        if (assembly_path.length > 0) {
            section("Assembly");
            field("Path", assembly_path);
        }

        return result;
    }

    /// JSON output
    JSONValue toJSON() const {
        string[string] res;

        void add(string key, string value) {
            if (value.length > 0)
                res[key] = value;
        }

        add("odood_version", odood_version);
        add("project_root", project_root);
        add("config_path", config_path);
        add("odoo_serie", odoo_serie);
        add("odoo_branch", odoo_branch);
        add("odoo_repo", odoo_repo);
        add("odoo_install_type", odoo_install_type);
        add("odoo_path", odoo_path);
        add("python_version", python_version);
        add("lodoo_version", lodoo_version);
        add("venv_path", venv_path);
        add("db_host", db_host);
        add("db_port", db_port);
        add("db_user", db_user);
        add("http_host", http_host);
        add("http_port", http_port);
        add("server_supervisor", server_supervisor);
        add("server_user", server_user);
        add("assembly_path", assembly_path);

        return JSONValue(res);
    }
}


/** Collect static environment info about the project.
  *
  * Uses UFCS pattern — call as project.getInfo().
  **/
ProjectInfo getInfo(in Project project) {
    ProjectInfo info;

    // Odood
    info.odood_version = _version;

    // Project
    info.project_root = project.project_root.toString;
    info.config_path = project.config_path.toString;

    // Odoo
    info.odoo_serie = project.odoo.serie.toString;
    info.odoo_branch = project.odoo.branch;
    info.odoo_repo = project.odoo.repo;
    info.odoo_install_type = project.odoo_install_type == OdooInstallType.Git
        ? "git" : "archive";
    info.odoo_path = project.odoo.path.toString;

    // Python / Virtualenv
    info.python_version = project.venv.py_version.toString;
    info.venv_path = project.venv.path.toString;

    // LOdoo version — parse from pip show output
    try {
        auto pip_result = project.venv.pip("show", "lodoo");
        foreach (line; pip_result.output.split("\n")) {
            if (line.startsWith("Version:")) {
                info.lodoo_version = line["Version:".length .. $].strip;
                break;
            }
        }
    } catch (Exception) {
        info.lodoo_version = "";
    }

    // Database config from odoo.conf
    try {
        auto db_config = parseOdooDatabaseConfig(project);
        info.db_host = db_config.host ? db_config.host : "";
        info.db_port = db_config.port ? db_config.port : "";
        info.db_user = db_config.user ? db_config.user : "";
    } catch (Exception) {
        // odoo.conf may not exist yet
    }

    // HTTP config from odoo.conf
    try {
        auto http_config = project.server.getConfigHTTP();
        info.http_host = http_config.host;
        info.http_port = http_config.port.to!string;
    } catch (Exception) {
        // odoo.conf may not exist yet
    }

    // Server management
    final switch (project.odoo.server_supervisor) {
        case ProjectServerSupervisor.Odood:
            info.server_supervisor = "odood";
            break;
        case ProjectServerSupervisor.InitScript:
            info.server_supervisor = "init-script";
            break;
        case ProjectServerSupervisor.Systemd:
            info.server_supervisor = "systemd";
            break;
    }
    info.server_user = project.odoo.server_user;

    // Assembly
    if (project.assembly !is null)
        info.assembly_path = project.assembly.path.toString;

    return info;
}
