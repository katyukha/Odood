module odood.cli.init;

private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.command: OdoodCommand;
private import odood.lib.project: Project, ProjectConfig;
private import odood.lib.odoo_serie: OdooSerie;
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
        this.add(new Flag(null, "archive", "Download odoo as archive"));
        this.add(new Flag(null, "git", "Clone odoo as git repository."));
        this.add(new Flag(null, "single-branch", "Clone odoo as single-branch git repository."));

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

        return ProjectConfig(
                install_dir,
                odoo_version,
                odoo_branch,
                odoo_repo);
    }

    public override void execute(ProgramArgs args) {
        auto project_config = this.initProjectConfig(args);
        auto project = Project(project_config);
        project.initialize();
        project.save();
    }

}

