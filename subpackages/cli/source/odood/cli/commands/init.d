module odood.cli.commands.init;

private import std.logger;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.odoo.config: initOdooConfig;
private import odood.lib.postgres: createNewPostgresUser;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.exception: OdoodException;


class CommandInit: OdoodCommand {
    this() {
        super("init", "Initialize new odood project.");
        this.add(new Option("i", "install-dir", "Directory to install odoo to")
            .required());
        this.add(new Option("v", "odoo-version", "Version of Odoo to install")
            .required().defaultValue("14.0"));
        this.add(new Option(
            null, "odoo-branch", "Branch in Odoo repo to install Odoo from."));
        this.add(new Option(
            null, "odoo-repo", "Install Odoo from specific repository."));
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
            null, "create-db-user",
            "[sudo] Create database user automatically during installation." ~
            "Requires sudo."));
        this.add(new Option(
            null, "http-host", "Http host").defaultValue("0.0.0.0"));
        this.add(new Option(
            null, "http-port", "Http port").defaultValue("8069"));
    }

    auto prepareOdooConfig(in Project project, ProgramArgs args) {
        auto odoo_config = initOdooConfig(project);
        odoo_config["options"].setKey("db_host", args.option("db-host"));
        odoo_config["options"].setKey("db_port", args.option("db-port"));
        odoo_config["options"].setKey("db_user", args.option("db-user"));
        odoo_config["options"].setKey(
            "db_password", args.option("db-password"));

        if (project.odoo.serie < OdooSerie(11)) {
            odoo_config["options"].setKey(
                "xmlrpc_interface", args.option("http-host"));
            odoo_config["options"].setKey(
                "xmlrpc_port", args.option("http-port"));
        } else {
            odoo_config["options"].setKey(
                "http_interface", args.option("http-host"));
            odoo_config["options"].setKey(
                "http_port", args.option("http-port"));
        }
        return odoo_config;
    }

    public override void execute(ProgramArgs args) {
        auto install_dir = Path(args.option("install-dir"));
        auto odoo_version = OdooSerie(args.option("odoo-version"));
        auto odoo_branch = args.option("odoo-branch", odoo_version.toString());
        auto odoo_repo = args.option(
                "odoo-repo", "https://github.com/odoo/odoo.git");

        enforce!OdoodException(
            odoo_version.isValid,
            "Odoo version %s is not valid".format(args.option("odoo-version")));

        auto project = new Project(
            install_dir,
            odoo_version,
            odoo_branch,
            odoo_repo);

        auto odoo_config = prepareOdooConfig(project, args);

        project.initialize(
            odoo_config,
            args.option("py-version", "auto"),
            args.option("node-version", "lts"));
        project.save();

        if (args.flag("create-db-user")) {
            infof(
                "Creating new postgres user %s for Odood project %s",
                args.option("db-user"), project.project_root);
            createNewPostgresUser(
                args.option("db-user"), args.option("db-password"));
        }

    }

}

