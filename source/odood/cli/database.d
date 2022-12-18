module odood.cli.database;

private import std.stdio;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.command: OdoodCommand;
private import odood.lib.project: Project, ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.exception: OdoodException;


class CommandDatabaseList: OdoodCommand {
    this() {
        super("list", "Show the databases available for this odoo.");
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        foreach(db; project.lodoo.listDatabases()) {
            writeln("- %s".format(db));
        }
    }

}


class CommandDatabase: OdoodCommand {
    this() {
        super("db", "Database management commands");
        this.add(new CommandDatabaseList());
    }
}


