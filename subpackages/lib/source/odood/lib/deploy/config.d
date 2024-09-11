module odood.lib.deploy.config;

private import std.conv: to;

private import thepath: Path;

private import odood.lib.odoo.config: initOdooConfig;
private import odood.lib.project: Project, OdooInstallType;
private import odood.lib.project.config: ProjectServerSupervisor;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils: generateRandomString;

immutable auto DEFAULT_PASSWORD_LEN = 32;


struct DeployConfigDatabase {
    string host="localhost";
    string port="5432";
    string user="odoo";
    string password;
    bool local_postgres=false;
}

struct DeployConfigOdoo {
    OdooSerie serie;
    bool proxy_mode=false;
    string http_host="localhost";
    string http_port="8069";
    uint workers=0;

    string server_user="odoo";
    ProjectServerSupervisor server_supervisor=ProjectServerSupervisor.Systemd;

}

struct DeployConfig {
    Path deploy_path = Path("/", "opt", "odoo");
    string py_version="auto";
    string node_version="lts";
    OdooInstallType install_type=OdooInstallType.Archive;

    DeployConfigDatabase database;
    DeployConfigOdoo odoo;

    auto prepareOdooConfig(in Project project) const
    in (
        project.odoo.serie == this.odoo.serie
    ) {
        auto odoo_config = initOdooConfig(project);
        odoo_config["options"].setKey(
            "admin_passwd", generateRandomString(DEFAULT_PASSWORD_LEN));

        // DB config
        odoo_config["options"].setKey("db_host", database.host);
        odoo_config["options"].setKey("db_port", database.port);
        odoo_config["options"].setKey("db_user", database.user);
        odoo_config["options"].setKey("db_password", database.password);

        if (odoo.serie < OdooSerie(11)) {
            odoo_config["options"].setKey("xmlrpc_interface", odoo.http_host);
            odoo_config["options"].setKey("xmlrpc_port", odoo.http_port);
        } else {
            odoo_config["options"].setKey("http_interface", odoo.http_host);
            odoo_config["options"].setKey("http_port", odoo.http_port);
        }

        odoo_config["options"].setKey("workers", odoo.workers.to!string);

        if (odoo.proxy_mode)
            odoo_config["options"].setKey("proxy_mode", "True");

        return odoo_config;
    }
}
