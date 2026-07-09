module odood.cli.commands.deploy;

private import core.sys.posix.unistd: geteuid, getegid;

private import std.logger;
private import std.format: format;
private import std.exception: enforce, errnoEnforce;
private import std.conv: octal, to;
private import std.range: empty;
private import std.typecons: nullable, Nullable;

private import thepath: Path;
private import theprocess: Process;
private import darkcommand;
private import dini: Ini;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.project:
    Project, OdooInstallType;
private import odood.project.config: ProjectServerSupervisor;
private import odood.lib.python.venv: PyInstallType, VenvOptions;
private import odood.lib.python.odoo: guessVenvOptions;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils: generateRandomString;
private import odood.git: GitURL;

private import odood.project.deploy;
private import odood.project.deploy.config: detectSystemCABundle;


class CommandDeploy: OdoodCommand {
    string odooVersion = "17.0";
    Nullable!string pyVersion;
    Nullable!string nodeVersion;
    string dbHost = "localhost";
    string dbPort = "False";
    string dbUser = "odoo";
    Nullable!string dbPassword;
    bool localPostgres;
    string workers = "0";
    bool proxyMode;
    bool localNginx;
    Nullable!string localNginxServerName;
    bool localNginxSsl;
    Nullable!string localNginxSslCert;
    Nullable!string localNginxSslKey;
    bool tls12Compat;
    bool letsencrypt;
    Nullable!string letsencryptEmail;
    bool enableLogrotate;
    bool enableFail2ban;
    string supervisor = "systemd";
    bool logToStderr;
    bool useSystemCaBundle;
    Nullable!string assemblyRepo;
    Nullable!string serverUserUid;
    Nullable!string serverUserGid;

    this() {
        super("deploy", "Deploy production-ready Odoo.");
        this.addOption!(odooVersion)("v", "odoo-version", "Version of Odoo to install")
            .defaultValue("17.0");
        this.addOption!(pyVersion)("", "py-version", "Install specific python version.");
        this.addOption!(nodeVersion)("", "node-version", "Install specific node version.");

        this.addOption!(dbHost)("", "db-host", "Database host").defaultValue("localhost");
        this.addOption!(dbPort)("", "db-port", "Database port").defaultValue("False");
        this.addOption!(dbUser)("", "db-user", "Database user").defaultValue("odoo");
        this.addOption!(dbPassword)("", "db-password", "Database password");
        this.addFlag!(localPostgres)("", "local-postgres",
            "Configure local postgresql server (requires PostgreSQL installed)");

        this.addOption!(workers)("w", "workers",
            "Number of workers to apply for this instance. If set to 0, then Odoo will be started in threaded mode. Default: 0")
            .defaultValue("0");

        this.addFlag!(proxyMode)("", "proxy-mode", "Enable proxy-mode in odoo config");

        this.addFlag!(localNginx)("", "local-nginx",
            "Autoconfigure local nginx (requires nginx installed)");
        this.addOption!(localNginxServerName)("", "local-nginx-server-name",
            "Servername for nginx config.");
        this.addFlag!(localNginxSsl)("", "local-nginx-ssl", "Enable SSL for local nginx");
        this.addOption!(localNginxSslCert)("", "local-nginx-ssl-cert",
            "Path to SSL certificate for local nginx.")
            .acceptsFiles();
        this.addOption!(localNginxSslKey)("", "local-nginx-ssl-key",
            "Path to SSL key for local nginx.")
            .acceptsFiles();

        this.addFlag!(tls12Compat)("", "tls12-compat",
            "Allow TLS 1.2 in addition to TLS 1.3 for backward compatibility with older clients. " ~
            "By default, only TLS 1.3 is enabled.");

        this.addFlag!(letsencrypt)("", "letsencrypt",
            "Enable Let's Encrypt configuration.");
        this.addOption!(letsencryptEmail)("", "letsencrypt-email",
            "Email for Let's Encrypt account.");

        this.addFlag!(enableLogrotate)("", "enable-logrotate",
            "Enable logrotate for Odoo.");

        this.addFlag!(enableFail2ban)("", "enable-fail2ban",
            "Enable fail2ban for Odoo (requires fail2ban installed).");

        this.addOption!(supervisor)("", "supervisor",
            "What supervisor to use for deployment. One of: odood, init-script, systemd. Default: systemd.")
            .defaultValue("systemd")
            .acceptsValues(["odood", "init-script", "systemd"]);

        this.addFlag!(logToStderr)("", "log-to-stderr",
            "Log to stderr. Useful when running inside docker.");

        this.addFlag!(useSystemCaBundle)("", "use-system-ca-bundle",
            "Set REQUESTS_CA_BUNDLE to the system CA certificate store, " ~
            "so Odoo uses system certificates instead of the bundled certifi CA bundle.");

        this.addOption!(assemblyRepo)("", "assembly-repo",
            "Configure Odood to use assembly from this repo. Ensure, you have access to specified repo from this machine.");

        this.addOption!(serverUserUid)("", "server-user-uid",
            "Create the Odoo system user with this fixed UID. Intended for " ~
            "container builds that need a deterministic UID matching the " ~
            "runtime securityContext. By default the UID is allocated dynamically.");
        this.addOption!(serverUserGid)("", "server-user-gid",
            "Create the Odoo system group with this fixed GID. " ~
            "Defaults to the UID value when omitted.");
    }

    DeployConfig parseDeployOptions() {
        DeployConfig config;
        config.odoo.serie = OdooSerie(odooVersion);

        config.venv_options = config.odoo.serie.guessVenvOptions;

        if (!pyVersion.isNull) {
            config.venv_options.py_version = pyVersion.get;
            config.venv_options.install_type = PyInstallType.Build;
        }
        if (!nodeVersion.isNull)
            config.venv_options.node_version = nodeVersion.get;

        config.database.host = dbHost;
        config.database.port = dbPort;
        config.database.user = dbUser;
        if (!dbPassword.isNull)
            config.database.password = dbPassword.get;

        if (proxyMode)
            config.odoo.proxy_mode = true;

        config.odoo.workers = workers.to!uint;

        if (localPostgres)
            config.database.local_postgres = true;

        if (config.database.local_postgres && config.database.password.empty)
            config.database.password = generateRandomString(DEFAULT_PASSWORD_LEN);

        if (enableLogrotate)
            config.logrotate_enable = true;

        if (localNginx || !localNginxServerName.isNull) {
            config.nginx.enable = true;
            config.nginx.server_name = localNginxServerName.isNull ? "" : localNginxServerName.get;
            config.nginx.ssl_on = localNginxSsl;

            if (config.nginx.ssl_on && !localNginxSslCert.isNull)
                config.nginx.ssl_cert = Path(localNginxSslCert.get);

            if (config.nginx.ssl_on && !localNginxSslKey.isNull)
                config.nginx.ssl_key = Path(localNginxSslKey.get);

            config.odoo.proxy_mode = true;
            config.odoo.http_host = "127.0.0.1";

            if (tls12Compat)
                config.nginx.tls12_compat = true;
        }
        if (letsencrypt || !letsencryptEmail.isNull) {
            config.letsencrypt_enable = true;
            config.letsencrypt_email = letsencryptEmail.isNull ? "" : letsencryptEmail.get;
            config.nginx.enable = true;
            config.nginx.ssl_on = true;
            config.nginx.ssl_key = Path("/", "etc", "letsencrypt", "live", config.nginx.server_name, "privkey.pem");
            config.nginx.ssl_cert = Path("/", "etc", "letsencrypt", "live", config.nginx.server_name, "fullchain.pem");
        }

        if (enableFail2ban)
            config.fail2ban_enable = true;

        switch(supervisor) {
            case "odood":
                config.odoo.server_supervisor = ProjectServerSupervisor.Odood;
                break;
            case "init-script":
                config.odoo.server_supervisor = ProjectServerSupervisor.InitScript;
                break;
            case "systemd":
                config.odoo.server_supervisor = ProjectServerSupervisor.Systemd;
                break;
            default:
                assert(0, "Not supported supervisor");
        }

        if (logToStderr)
            config.odoo.log_to_stderr = true;

        if (useSystemCaBundle) {
            config.odoo.use_system_ca_bundle = true;
            config.odoo.system_ca_bundle_path = detectSystemCABundle();
        }

        if (!assemblyRepo.isNull)
            config.assembly_repo = GitURL(assemblyRepo.get).nullable;

        if (!serverUserUid.isNull)
            config.odoo.server_user_uid = serverUserUid.get.to!uint.nullable;
        if (!serverUserGid.isNull)
            config.odoo.server_user_gid = serverUserGid.get.to!uint.nullable;

        return config;
    }

    void validateDeploy(in DeployConfig deploy_config) {
        enforce!OdoodCLIException(
            geteuid == 0 && getegid == 0,
            "This command must be ran as root!");
        deploy_config.ensureValid();
    }

    override int execute() {
        auto deploy_config = parseDeployOptions();
        validateDeploy(deploy_config);

        auto project = deployOdoo(deploy_config);
        return 0;
    }
}
