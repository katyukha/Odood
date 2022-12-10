module odood.cli.init;

private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.command: OdoodCommand;
private import odood.lib.project: Project, ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.exception: OdoodException;


class CommandInit: OdoodCommand {
    this() {
        super("init", "Initialize new odood project.");
        this.add(new Option("i", "install-dir", "Directory to install odoo to")
            .required());
        this.add(new Option(null, "odoo-version", "Version of Odoo to install")
            .required().defaultValue("14.0"));
        this.add(new Option(null, "odoo-branch", "Branch in Odoo repo to install Odoo from."));
        this.add(new Option(null, "odoo-repo", "Install Odoo from specific repository."));
        this.add(new Option(null, "py-version", "Install specific python version."));
        this.add(new Option(null, "node-version", "Install specific node version."));
    }

    ProjectConfig initProjectConfig(ProgramArgs args) {
        auto install_dir = Path(args.option("install-dir"));
        auto odoo_version = OdooSerie(args.option("odoo-version"));
        auto odoo_branch = args.option("odoo-branch", odoo_version.toString());
        auto odoo_repo = args.option(
                "odoo-repo", "https://github.com/odoo/odoo.git");

        enforce!OdoodException(
            odoo_version.isValid,
            "Odoo version %s is not valid".format(args.option("odoo-version")));

        auto config = ProjectConfig(
            install_dir,
            odoo_version,
            odoo_branch,
            odoo_repo);

        if (args.option("py-version")) {
            config.python_version = args.option("py-version");
        }
        if (args.option("node-version")) {
            config.node_version = args.option("node-version");
        }

        return config;
    }

    public override void execute(ProgramArgs args) {
        auto project_config = this.initProjectConfig(args);
        auto project = new Project(project_config);
        project.initialize();
        project.save();
    }

}

