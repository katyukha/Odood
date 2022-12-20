module odood.cli.commands.database;

private import std.stdio;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand, exitWithCode;
private import odood.lib.project: Project, ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;


class CommandDatabaseList: OdoodCommand {
    this() {
        super("list");
    }

    this(in string name) {
        super(name, "Show the databases available for this odoo.");
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        foreach(db; project.lodoo.listDatabases()) {
            writeln("- %s".format(db));
        }
    }

}


class CommandDatabaseCreate: OdoodCommand {
    this() {
        super("create", "Create new odoo database.");
        this.add(new Option(
            "l", "lang",
            "Language of database, specified as ISO code of language."
        ).defaultValue("en_US"));
        this.add(new Option(
            null, "password", "Admin password for this database."));
        this.add(new Option(
            null, "country", "Country for this db."));
        this.add(new Flag("d", "demo", "Load demo data for this db"));
        this.add(new Argument("name", "Name of database").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        project.lodoo.createDatabase(
            args.arg("name"),
            args.flag("demo"),
            args.option("lang"),
            args.option("password"),
            args.option("country"));
    }
}

class CommandDatabaseDrop: OdoodCommand {
    this() {
        super("drop", "Drop the odoo database.");
        this.add(new Argument("name", "Name of database").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        project.lodoo.dropDatabase(args.arg("name"));
    }
}


class CommandDatabaseExists: OdoodCommand {
    this() {
        super("exists", "Check if database exists.");
        this.add(new Flag(
            "-q", "quiet", "Suppress output, just return exit code"));
        this.add(new Argument("name", "Name of database").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        bool db_exists = project.lodoo.isDatabaseExists(args.arg("name"));
        if (db_exists) {
            if (!args.flag("quiet"))
                writeln("Database %s exists!".format(args.arg("name")));
            exitWithCode(0, "Database exists");
        } else {
            if (!args.flag("quiet"))
                writeln("Database does not %s exists!".format(args.arg("name")));
            exitWithCode(1, "Database does not exists");
        }
    }
}

class CommandDatabase: OdoodCommand {
    this() {
        super("db", "Database management commands");
        this.add(new CommandDatabaseList());
        this.add(new CommandDatabaseCreate());
        this.add(new CommandDatabaseDrop());
        this.add(new CommandDatabaseExists());
    }
}


