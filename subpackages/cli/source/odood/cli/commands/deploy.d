module odood.cli.commands.deploy;

private import core.sys.posix.unistd: geteuid, getegid;

private import std.logger;
private import std.format: format;
private import std.exception: enforce, errnoEnforce;
private import std.conv: octal;

private import thepath: Path;
private import theprocess: Process;
private import commandr: Option, Flag, ProgramArgs, acceptsValues;
private import dini: Ini;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.project:
    Project, OdooInstallType, ODOOD_SYSTEM_CONFIG_PATH;
private import odood.lib.project.config: ProjectServerSupervisor;
private import odood.lib.odoo.config: initOdooConfig;
private import odood.lib.postgres: createNewPostgresUser;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils: generateRandomString;

private import odood.lib.deploy;


class CommandDeploy: OdoodCommand {
    this() {
        super("deploy", "Deploy production-ready Odoo.");
        this.add(new Option("v", "odoo-version", "Version of Odoo to install")
            .required().defaultValue("17.0"));
        this.add(new Option(
            null, "py-version", "Install specific python version.")
                .defaultValue("auto"));
        this.add(new Option(
            null, "node-version", "Install specific node version.")
                .defaultValue("lts"));

        this.add(new Option(
            null, "db-host", "Database host").defaultValue("localhost"));
        this.add(new Option(
            null, "db-port", "Database port").defaultValue("False"));
        this.add(new Option(
            null, "db-user", "Database port").defaultValue("odoo"));
        this.add(new Option(
            null, "db-password", "Database password").defaultValue("odoo"));

        this.add(new Flag(
            null, "proxy-mode", "Enable proxy-mode in odoo config"));
    }

    DeployConfig parseDeployOptions(ProgramArgs args) {
        DeployConfig config;
        config.odoo.serie = OdooSerie(args.option("odoo-version"));

        if (args.option("py-version"))
            config.py_version = args.option("py-version");
        if (args.option("node-version"))
            config.node_version = args.option("node-version");

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
        return config;
    }

    void validateDeploy(ProgramArgs args, in DeployConfig deploy_config) {
        // TODO: move to odood.lib.deploy
        enforce!OdoodCLIException(
            geteuid == 0 && getegid == 0,
            "This command must be ran as root!");

        enforce!OdoodCLIException(
            deploy_config.odoo.serie.isValid,
            "Odoo version %s is not valid".format(args.option("odoo-version")));
        enforce!OdoodCLIException(
            !deploy_config.deploy_path.exists,
            "Deploy path %s already exists. ".format(deploy_config.deploy_path) ~
            "It seems that there was attempt to install Odoo. " ~
            "This command can install Odoo only on clean machine.");
        enforce!OdoodCLIException(
            !ODOOD_SYSTEM_CONFIG_PATH.exists,
            "Odood system-wide config already exists at %s. ".format(ODOOD_SYSTEM_CONFIG_PATH) ~
            "It seems that there was attempt to install Odoo. " ~
            "This command can install Odoo only on clean machine.");
        enforce!OdoodCLIException(
            !Path("etc", "logrotate.d", "odoo").exists,
            "It seems that Odoo config for logrotate already exists!");
        enforce!OdoodCLIException(
            !Path("etc", "systemd", "system", "odoo.service").exists,
            "It seems that systemd service for Odoo already exists!");
    }

    public override void execute(ProgramArgs args) {
        // TODO: run only as root
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


