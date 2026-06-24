module odood.cli.commands.script;

private import std.logger;
private import std.exception: enforce;
private import std.format: format;

private import darkcommand;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.project: Project;
private import odood.lib.odoo.script: resolveScriptPath;


class CommandScriptPy: OdoodCommand {
    string db;
    string script;

    this() {
        super("py", "Run Python script in this environment.");
        this.addOption!(db)("d", "db", "Database to run script for");
        this.addArgument!(script)("script",
            "Script to run: an absolute path, or a name resolved against " ~
            "<repo>/.odood-scripts/, <project>/scripts/, or the current directory.")
            // Offer file completion without requiring the value to be an
            // existing file, so bare names resolved against the convention
            // directories still work.
            .completesAsFile();
    }

    override int execute() {
        auto project = Project.loadProject;

        enforce!OdoodCLIException(
            project.databases.exists(db),
            "Database %s does not exists!".format(db));

        project.lodoo.runPyScript(db, resolveScriptPath(project, script));
        return 0;
    }
}


class CommandScriptSQL: OdoodCommand {
    string db;
    bool noCommit;
    string script;

    this() {
        super("sql", "Run SQL script in this environment.");
        this.addOption!(db)("d", "db", "Database to run script for");
        this.addFlag!(noCommit)("n", "no-commit", "Do not commit changes.");
        this.addArgument!(script)("script",
            "Script to run: an absolute path, or a name resolved against " ~
            "<repo>/.odood-scripts/, <project>/scripts/, or the current directory.")
            // Offer file completion without requiring the value to be an
            // existing file, so bare names resolved against the convention
            // directories still work.
            .completesAsFile();
    }

    override int execute() {
        auto project = Project.loadProject;

        enforce!OdoodCLIException(
            project.databases.exists(db),
            "Database %s does not exists!".format(db));

        project.dbSQL(db).runSQLScript(resolveScriptPath(project, script), noCommit);
        return 0;
    }
}


class CommandScript: OdoodCommand {
    this() {
        super("script", "Run scripts in Odood environment.");
        this.add(new CommandScriptPy());
        this.add(new CommandScriptSQL());
    }
}
