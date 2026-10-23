module odood.cli.commands.script;

private import std.stdio: writeln, writefln;
private import std.logger;
private import std.algorithm: any;
private import std.conv: to;
private import std.string: capitalize;
private import std.exception: enforce;
private import std.format: format;
private import std.json: JSONValue;

private import darkcommand;
private import colored;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.cli.utils: printJSON, displayPath;
private import odood.project: Project;
private import odood.project.odoo.script:
    resolveScriptPath, listScripts, ScriptGroup, ScriptSource;


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
        auto project = this.loadProject;

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
        auto project = this.loadProject;

        enforce!OdoodCLIException(
            project.databases.exists(db),
            "Database %s does not exists!".format(db));

        project.dbSQL(db).runSQLScript(resolveScriptPath(project, script), noCommit);
        return 0;
    }
}


/// Name of a script source, as used in output.
private string sourceLabel(in ScriptSource source) {
    final switch(source) {
        case ScriptSource.repository: return "repository";
        case ScriptSource.project:    return "project";
    }
}


class CommandScriptList: OdoodCommand {
    bool json;
    bool absolute;

    this() {
        super("list", "List scripts that can be run by name.");
        this.addFlag!(json)("", "json", "Output the script list as JSON.");
        this.addFlag!(absolute)("", "absolute",
            "Show absolute paths instead of paths relative to the project root.");
    }

    /// Source that provides a shadowed name.
    private string shadowedBy(in ScriptGroup[] groups, in string name) {
        foreach(group; groups)
            foreach(script; group.scripts)
                if (script.name == name)
                    return sourceLabel(group.source);
        assert(0, "Shadowed script %s has no shadowing source!".format(name));
    }

    private void displayJSON(in Project project, in ScriptGroup[] groups) {
        JSONValue[] result;
        foreach(group; groups) {
            JSONValue[] scripts;
            foreach(script; group.scripts)
                scripts ~= JSONValue([
                    "name": JSONValue(script.name),
                    "path": JSONValue(
                        displayPath(project.project_root, script.path, absolute)),
                    "type": JSONValue(script.type.to!string),
                    "shadowed": JSONValue(script.shadowed),
                ]);
            result ~= JSONValue([
                "source": JSONValue(sourceLabel(group.source)),
                "directory": JSONValue(
                    displayPath(project.project_root, group.directory, absolute)),
                "scripts": JSONValue(scripts),
            ]);
        }
        printJSON(JSONValue(result));
    }

    private void displayList(in Project project, in ScriptGroup[] groups) {
        foreach(i, group; groups) {
            if (i > 0)
                writeln();
            writefln(
                "%s (%s):",
                "%s scripts".format(sourceLabel(group.source).capitalize).bold,
                displayPath(project.project_root, group.directory, absolute));

            if (group.scripts.length == 0) {
                writeln("    (no scripts)");
                continue;
            }

            foreach(script; group.scripts)
                if (script.shadowed)
                    writefln(
                        "    %s",
                        "%s (shadowed by the %s script)".format(
                            script.name,
                            shadowedBy(groups, script.name)).yellow);
                else
                    writefln("    %s", script.name);
        }

        if (!groups.any!(g => g.source == ScriptSource.repository))
            writeln(
                "\nNot inside a git repository, thus no repository scripts " ~
                "are listed. Run this from a repository to see its " ~
                ".odood-scripts/ directory.");
    }

    override int execute() {
        auto project = this.loadProject;
        auto groups = listScripts(project);

        if (json)
            displayJSON(project, groups);
        else
            displayList(project, groups);
        return 0;
    }
}


class CommandScript: OdoodCommand {
    this() {
        super("script", "Run scripts in Odood environment.");
        this.add(new CommandScriptList());
        this.add(new CommandScriptPy());
        this.add(new CommandScriptSQL());
    }
}
