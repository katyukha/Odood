module odood.cli.commands.discover;

private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.project.discover: discoverOdooHelper;
private import odood.utils.odoo.serie: OdooSerie;


class CommandDiscoverOdooHelper: OdoodCommand {
    this() {
        super("odoo-helper", "Discover odoo-helper-scripts project.");
        this.add(new Flag(
            "s", "system",
            "Discover system (server-wide) odoo-helper project installation."));
        this.add(new Argument(
            "path", "Try to discover odoo-helper project in specified path."
        ).optional);
    }

    public override void execute(ProgramArgs args) {
        auto search_path = args.flag("system") ?
            Path("/", "etc", "odoo-helper.conf") :
            args.arg("path") ?
                Path(args.arg("path")) :
                Path.current;
        auto project = discoverOdooHelper(search_path);
        if (args.flag("system"))
            project.save(Path("/", "etc", "odood.yml"));
        else
            project.save();
        project.venv.ensureRunInVenvExists();
    }
}


class CommandDiscover: OdoodCommand {
    this() {
        super(
            "discover",
            "Discover already installed odoo, " ~
            "and configure Odood to manage it.");
        this.add(new CommandDiscoverOdooHelper());
    }
}
