module odood.cli.commands.deploy;

private import core.sys.posix.unistd: geteuid, getegid;

private import std.logger;
private import std.format: format;
private import std.exception: enforce, errnoEnforce;
private import std.conv: octal;
private import std.range: empty;

private import thepath: Path;
private import theprocess: Process;
private import commandr: Option, Flag, ProgramArgs, acceptsValues;
private import dini: Ini;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.project:
    Project, OdooInstallType;
private import odood.lib.project.config: ProjectServerSupervisor;
private import odood.lib.odoo.config: initOdooConfig;
private import odood.lib.venv: PyInstallType, VenvOptions;
private import odood.lib.odoo.python: guessVenvOptions;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils: generateRandomString;

private import odood.lib.deploy;


class CommandDeploy: OdoodCommand {
    this() {
        super("deploy", "Deploy production-ready Odoo.");
        this.add(new Option("v", "odoo-version", "Version of Odoo to install")
            .required().defaultValue("17.0"));
        this.add(new Option(
            null, "py-version", "Install specific python version."));
        this.add(new Option(
            null, "node-version", "Install specific node version."));

        this.add(new Option(
            null, "db-host", "Database host").defaultValue("localhost"));
        this.add(new Option(
            null, "db-port", "Database port").defaultValue("False"));
        this.add(new Option(
            null, "db-user", "Database port").defaultValue("odoo"));
        this.add(new Option(
            null, "db-password", "Database password"));
        this.add(new Flag(
            null, "local-postgres", "Configure local postgresql server (requires PostgreSQL installed)"));

        this.add(new Flag(
            null, "proxy-mode", "Enable proxy-mode in odoo config"));

        // TODO: Add support for automatic integration with certbot
        this.add(new Flag(
            null, "local-nginx", "Autoconfigure local nginx (requires nginx installed)"));
        this.add(new Option(
            null, "local-nginx-server-name", "Servername for nginx config."));
        this.add(new Flag(
            null, "local-nginx-ssl", "Enable SSL for local nginx"));
        this.add(new Option(
            null, "local-nginx-ssl-cert", "Path to SSL certificate for local nginx."));
        this.add(new Option(
            null, "local-nginx-ssl-key", "Path to SSL key for local nginx."));

        this.add(new Flag(
            null, "enable-logrotate", "Enable logrotate for Odoo."));

        this.add(new Flag(
            null, "enable-fail2ban", "Enable fail2ban for Odoo (requires fail2ban installed)."));

        this.add(new Option(
            null, "supervisor", "What superwisor to use for deployment. One of: odood, init-script, systemd. Default: systemd.")
                .defaultValue("systemd")
                .acceptsValues(["odood", "init-script", "systemd"]));

        this.add(new Flag(
            null, "log-to-stderr", "Log to stderr. Useful when running inside docker."));

        // TODO: Add option to automatically install extra dependencies (including wktmltopdf)
        //       Ensure that Odood can do it automatically
    }

    DeployConfig parseDeployOptions(ProgramArgs args) {
        DeployConfig config;
        config.odoo.serie = OdooSerie(args.option("odoo-version"));

        config.venv_options = config.odoo.serie.guessVenvOptions;

        if (args.option("py-version")) {
            config.venv_options.py_version = args.option("py-version");
            config.venv_options.install_type = PyInstallType.Build;
        }
        if (args.options("node-version")) {
            config.venv_options.node_version = args.option("node-version");
        }

        if (args.option("db-host"))
            config.database.host = args.option("db-host");
        if (args.option("db-port"))
            config.database.port = args.option("db-port");
        if (args.option("db-user"))
            config.database.user = args.option("db-user");
        if (args.option("db-password"))
            config.database.password = args.option("db-password");

        if (args.flag("proxy-mode"))
            config.odoo.proxy_mode = true;

        if (args.flag("local-postgres"))
            config.database.local_postgres = true;

        if (config.database.local_postgres && config.database.password.empty)
            /* Generate default password.
             * Here we assume that new user will be created in local postgres.
             * Most likely case.
             */
            config.database.password = generateRandomString(
                    DEFAULT_PASSWORD_LEN);

        if (args.flag("enable-logrotate"))
            config.logrotate_enable = true;

        if (args.flag("local-nginx")) {
            config.nginx.enable = true;
            config.nginx.server_name = args.option("local-nginx-server-name");
            config.nginx.ssl_on = args.flag("local-nginx-ssl");

            if (config.nginx.ssl_on && !args.option("local-nginx-ssl-cert").empty)
                config.nginx.ssl_cert = Path(args.option("local-nginx-ssl-cert"));

            if (config.nginx.ssl_on && !args.option("local-nginx-ssl-key").empty)
                config.nginx.ssl_key = Path(args.option("local-nginx-ssl-key"));

            config.odoo.proxy_mode = true;
            config.odoo.http_host = "127.0.0.1";
        }

        if (args.flag("enable-fail2ban"))
            config.fail2ban_enable = true;

        if (args.option("supervisor"))
            switch(args.option("supervisor")) {
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

        if (args.flag("log-to-stderr"))
            config.odoo.log_to_stderr = true;

        return config;
    }

    void validateDeploy(ProgramArgs args, in DeployConfig deploy_config) {
        // TODO: move to odood.lib.deploy
        enforce!OdoodCLIException(
            geteuid == 0 && getegid == 0,
            "This command must be ran as root!");
        deploy_config.ensureValid();
    }

    public override void execute(ProgramArgs args) {
        /* Plan:
         * 0. Update locales
         * 1. Deploy Odoo in /opt/odoo
         * 2. Create system user
         * 3. Set access rights for Odoo
         * 4. Prepare systemd configuration for Odoo
         * 5. Install postgres if needed
         * 6. Create postgres user if needed
         * 7. Configure logrotate
         * 8. Install nginx if needed
         * 9. Configure Odoo
         */
        auto deploy_config = parseDeployOptions(args);
        validateDeploy(args, deploy_config);

        auto project = deployOdoo(deploy_config);
    }

}


