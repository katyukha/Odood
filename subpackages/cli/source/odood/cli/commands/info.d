/// Print info about current Odood project
module odood.cli.commands.info;

private import std.json;
private import std.stdio;

private import colored;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;


class CommandInfo: OdoodCommand {
    this() {
        super("info", "Print info about this Odood project.");
        this.add(new Flag(null, "json", "Print output in json format"));
    }

    private string[string] prepareInfo(ProgramArgs args, in Project project) const {
        string[string] res = [
            "odoo_version": project.odoo.serie.toString,
            "odoo_branch": project.odoo.branch,
            "odoo_repository": project.odoo.repo,
            "python_version": project.venv.py_version.toString,
        ];

        // TODO: Add postgres version, and other info

        return res;
    }

    /// Print project info as text
    private void printInfoText(ProgramArgs args, in Project project) const {
        foreach(i; prepareInfo(args, project).byKeyValue)
            writefln("%s: %s", i.key, i.value);
    }

    /// Print project info as json
    private void printInfoJSON(ProgramArgs args, in Project project) const {
        auto info = JSONValue(prepareInfo(args, project));
        info.toJSON(true).writeln;
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        if (args.flag("json"))
            printInfoJSON(args, project);
        else
            printInfoText(args, project);
    }
}


