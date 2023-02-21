module odood.cli.commands.discover;

private import std.stdio;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.exception: OdoodException;
private import odood.lib.project.discover: discoverOdooHelper;


class CommandDiscoverOdooHelper: OdoodCommand {
    this() {
        super("odoo-helper", "Discover odoo-helper-scripts project.");
        this.add(new Argument(
            "path", "Try to discover odoo-helper project in specified path."
        ).optional);
    }

    public override void execute(ProgramArgs args) {
        auto project = discoverOdooHelper(
                args.arg("path") ? Path(args.arg("path")) : Path.current);
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
