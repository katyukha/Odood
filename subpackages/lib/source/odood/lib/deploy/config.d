module odood.lib.deploy.config;

private import std.conv: to;
private import std.range: empty;
private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable;

private import thepath: Path;
private import theprocess: Process, resolveProgram;

private import odood.lib.odoo.config: initOdooConfig;
private import odood.lib.project:
    Project,
    OdooInstallType,
    ODOOD_SYSTEM_CONFIG_PATH;
private import odood.lib.project.config:
    ProjectServerSupervisor,
    ProjectConfigDirectories,
    ProjectConfigOdoo;
private import odood.lib.deploy.exception: OdoodDeployException;
private import odood.lib.venv: VenvOptions, PyInstallType;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils: generateRandomString, checkSystemUserExists;
private import odood.git: GitURL;

immutable auto DEFAULT_PASSWORD_LEN = 32;


/** Odoo database cofiguration to be deployed
  **/
struct DeployConfigDatabase {
    string host="localhost";
    string port="5432";
    string user="odoo";
    string password;
    bool local_postgres=false;
}


/** Odoo configuration to be deployed
  **/
struct DeployConfigOdoo {
    OdooSerie serie;
    bool proxy_mode=false;
    string http_host=null;
    string http_port="8069";
    string websocket_port="8072";
    uint workers=0;

    string server_user="odoo";
    // TODO: Add configuration to automatically patch system config to use system ssl certificates for requests
    ProjectServerSupervisor server_supervisor=ProjectServerSupervisor.Systemd;
    Path server_init_script_path = Path(
        "/", "etc", "init.d", "odoo");
    Path server_systemd_service_path = Path(
        "/", "etc", "systemd", "system", "odoo.service");

    Path pidfile = Path("/", "var", "run", "odoo.pid");

    bool log_to_stderr = false;
}


/** Configuration for nginx deployment
  **/
struct DeployConfigNginx {
    bool enable = false;
    string server_name = null;


    bool ssl_on = false;
    Path ssl_cert = Path("/", "etc", "nginx", "ssl", "server.crt");
    Path ssl_key = Path("/", "etc", "nginx", "ssl", "server.key");

    Path config_path = Path("/", "etc", "nginx", "conf.d", "odoo.conf");
}


/** Deploy configuration
  **/
struct DeployConfig {
    Path deploy_path = Path("/", "opt", "odoo");
    VenvOptions venv_options;
    OdooInstallType install_type=OdooInstallType.Archive;

    DeployConfigDatabase database;
    DeployConfigOdoo odoo;

    bool logrotate_enable = false;
    Path logrotate_config_path = Path("/", "etc", "logrotate.d", "odoo");

    DeployConfigNginx nginx;

    bool fail2ban_enable = false;
    Path fail2ban_filter_path = Path("/", "etc", "fail2ban", "filter.d", "odoo-auth.conf");
    Path fail2ban_jail_path = Path("/", "etc", "fail2ban", "jail.d", "odoo-auth.conf");

    bool letsencrypt_enable = false;
    string letsencrypt_email = null;
    Path letsencrypt_webroot = Path("/", "var", "/var/acme_challenge_webroot");
    uint letsencrypt_rsa_key_size = 4096;

    Nullable!GitURL assembly_repo;

    /** Validate deploy config
      * Throw exception if config is not valid.
      **/
    void ensureValid() const {
        enforce!OdoodDeployException(
            this.odoo.serie.isValid,
            "Odoo version is not valid");
        enforce!OdoodDeployException(
            !this.deploy_path.exists,
            "Deploy path %s already exists. ".format(this.deploy_path) ~
            "It seems that there was attempt to install Odoo. " ~
            "This command can install Odoo only on clean machine.");
        enforce!OdoodDeployException(
            !ODOOD_SYSTEM_CONFIG_PATH.exists,
            "Odood system-wide config already exists at %s. ".format(ODOOD_SYSTEM_CONFIG_PATH) ~
            "It seems that there was attempt to install Odoo. " ~
            "This command can install Odoo only on clean machine.");

        if (this.venv_options.install_type == PyInstallType.PyEnv) {
            // Ensure that pyenv is available, when user requests installation via pyenv
            enforce!OdoodDeployException(!resolveProgram("pyenv").isNull, "pyenv not available!");
        }

        if (this.logrotate_enable)
            enforce!OdoodDeployException(
                !Path("etc", "logrotate.d", "odoo").exists,
                "It seems that Odoo config for logrotate already exists!");

        final switch(this.odoo.server_supervisor) {
            case ProjectServerSupervisor.Odood:
                // Do nothing, no additional check needed.
                break;
            case ProjectServerSupervisor.InitScript:
                enforce!OdoodDeployException(
                    !this.odoo.server_init_script_path.exists,
                    "It seems that init.d script for Odoo already exists!");
                break;
            case ProjectServerSupervisor.Systemd:
                enforce!OdoodDeployException(
                    !this.odoo.server_systemd_service_path.exists,
                    "It seems that systemd service for Odoo already exists!");
                break;
        }

        enforce!OdoodDeployException(
            !this.database.password.empty,
            "Password for database must not be empty!");

        if (this.database.local_postgres)
            // If local postgres requested, we expect that `postgres` user exists in system.
            enforce!OdoodDeployException(
                checkSystemUserExists("postgres"),
                "Local postgres requested, but 'postgresql' package seems not installed!");

        if (this.nginx.enable)
            // If local nginx requested, ensure it is installed
            Process("nginx")
                .withArgs("-v")
                .execute
                .ensureOk!OdoodDeployException(
                    "Local Nginx requested, but it seems that nginx is not installed!", true);

        if (this.fail2ban_enable)
            Process("fail2ban-client")
                .withArgs("--version")
                .execute
                .ensureOk!OdoodDeployException(
                    "Enable fail2ban requested, but it seems that fail2ban is not available", true);
        if (this.nginx.ssl_on && !this.letsencrypt_enable) {
            // Check SSL keys only if let's encrypt not enabled.
            // In case of let's encrypt, we expect that SSL will be generated after installation.
            enforce!OdoodDeployException(
                this.nginx.ssl_key.exists(),
                "SSL enabled, but provided SSL key (%s) does not exists!".format(this.nginx.ssl_key));
            enforce!OdoodDeployException(
                this.nginx.ssl_cert.exists(),
                "SSL enabled, but provided SSL certificate (%s) does not exists!".format(this.nginx.ssl_cert));
        }

        if (this.letsencrypt_enable) {
            enforce!OdoodDeployException(
                !this.letsencrypt_email.empty,
                "Let's Encrypt enabled, but lets encrypt email is not specified.");
            enforce!OdoodDeployException(
                !this.nginx.enable,
                "Let's Encrypt enabled, but local nginx is not enabled.");
            enforce!OdoodDeployException(
                !this.nginx.ssl_on,
                "Let's Encrypt enabled, but local nginx ssl is not enabled.");
            enforce!OdoodDeployException(
                !this.nginx.server_name,
                "Let's Encrypt enabled, server-name not specified.");
            Process("certbot")
                .withArgs("--version")
                .execute
                .ensureOk!OdoodDeployException(
                    "Let's Encrypt enabled, but certbot is not installed.");
        }
    }

    /** Prepare odoo configuration file for this deployment
      * based on this deployment configuration
      **/
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
            if (odoo.http_host.length > 0)
                odoo_config["options"].setKey("xmlrpc_interface", odoo.http_host);
            odoo_config["options"].setKey("xmlrpc_port", odoo.http_port);
        } else {
            if (odoo.http_host.length > 0)
                odoo_config["options"].setKey("http_interface", odoo.http_host);
            odoo_config["options"].setKey("http_port", odoo.http_port);
        }

        // TODO: Configure automatically, set memory limits based on available RAM and CPU
        odoo_config["options"].setKey("workers", odoo.workers.to!string);

        if (odoo.proxy_mode || nginx.enable)
            odoo_config["options"].setKey("proxy_mode", "True");

        if (odoo.log_to_stderr)
            odoo_config["options"].removeKey("logfile");

        return odoo_config;
    }

    /** Prepare Odood project for deployment
      **/
    auto prepareOdoodProject() const {
        auto project_directories = ProjectConfigDirectories(this.deploy_path);
        auto project_odoo = ProjectConfigOdoo(
            this.deploy_path, project_directories, this.odoo.serie);
        project_odoo.server_user = this.odoo.server_user;
        project_odoo.server_supervisor = this.odoo.server_supervisor;
        project_odoo.server_systemd_service_path = this.odoo.server_systemd_service_path;
        project_odoo.server_init_script_path = this.odoo.server_init_script_path;
        project_odoo.pidfile = this.odoo.pidfile;

        /* On deployment, there is only one config file.
         * There is no need for separate config file for tests,
         * because if it is test machine, then it will be used only for tests.
         * separate test configfile is useful mostly for local development
         */
        project_odoo.testconfigfile = project_odoo.configfile;

        return new Project(
            this.deploy_path,
            project_directories,
            project_odoo);
    }
}
