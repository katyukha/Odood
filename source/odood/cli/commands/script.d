module odood.cli.commands.script;

private import std.logger;
private import std.exception: enforce;
private import std.format: format;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import thepath;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.exception: OdoodException;


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

        enforce!OdoodException(
            project.lodoo.databaseExists(args.option("db")),
            "Database %s does not exists!".format(args.option("db")));

        infof("Running python script %s for databse %s ...", script, dbname);
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

        enforce!OdoodException(
            project.lodoo.databaseExists(args.option("db")),
            "Database %s does not exists!".format(args.option("db")));

        infof("Running SQL script %s for databse %s ...", script, dbname);
        auto conn = project.dbConnect(dbname);
        conn.exec("BEGIN");  // Start new transaction
        auto res = conn.exec(script.readFileText);
        infof("SQL script %s for database %s completed!\n", script, dbname);
        if (args.flag("no-commit")) {
            warningf("Rollback, because --no-commit option supplied!");
            conn.exec("ROLLBACK");
        } else {
            conn.exec("COMMIT");
        }
    }
}



class CommandScript: OdoodCommand {
    this() {
        super("script", "Run scripts in Odood environment.");
        this.add(new CommandScriptPy());
        this.add(new CommandScriptSQL());
    }
}
