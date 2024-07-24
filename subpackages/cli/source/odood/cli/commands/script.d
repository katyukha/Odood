module odood.cli.commands.script;

private import std.logger;
private import std.exception: enforce;
private import std.format: format;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import thepath: Path;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.project: Project;


class CommandScriptPy: OdoodCommand {
    this() {
        super("py", "Run Python script in this environment.");
        this.add(new Option("d", "db", "Database to run script for").required);
        this.add(new Argument("script", "Path to script to run"));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto dbname = args.option("db");
        Path script = args.arg("script");

        enforce!OdoodCLIException(
            project.databases.exists(args.option("db")),
            "Database %s does not exists!".format(args.option("db")));

        auto res = project.lodoo.runPyScript(dbname, script);
        infof(
            "Python script %s for database %s completed!\nOutput:\n%s",
            script, dbname, res.output);
    }
}


class CommandScriptSQL: OdoodCommand {
    this() {
        super("sql", "Run SQL script in this environment.");
        this.add(new Option("d", "db", "Database to run script for").required);
        this.add(new Flag("n", "no-commit", "Do not commit changes."));
        this.add(new Argument("script", "Path to script to run"));
    }

    public override void execute(ProgramArgs args) {
        import dpq.query;
        auto project = Project.loadProject;

        auto dbname = args.option("db");
        Path script = args.arg("script");

        enforce!OdoodCLIException(
            project.databases.exists(dbname),
            "Database %s does not exists!".format(dbname));

        auto db = project.dbSQL(dbname);
        scope(exit) db.close();
        db.runSQLScript(script, args.flag("no-commit"));
    }
}



class CommandScript: OdoodCommand {
    this() {
        super("script", "Run scripts in Odood environment.");
        this.add(new CommandScriptPy());
        this.add(new CommandScriptSQL());
    }
}
