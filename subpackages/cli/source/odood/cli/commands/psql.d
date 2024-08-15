module odood.cli.commands.psql;

private import std.logger;
private import std.format: format;
private import std.conv: to, ConvException;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import theprocess: Process;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;


class CommandPSQL: OdoodCommand {
    this() {
        super("psql", "Run psql for specified database");
        this.add(new Option(
            "d", "db", "Name of database to connect to.").required);
    }

    public override void execute(ProgramArgs args) {
        Project.loadProject.psql
            .withEnv("PGDATABASE", args.option("db"))
            .execv;
    }
}

