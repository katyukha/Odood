/// Print info about current Odood project
module odood.cli.commands.info;

private import std.json: toJSON;
private import std.stdio: writeln;

private import commandr: Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.project.info: getInfo;


class CommandInfo: OdoodCommand {
    this() {
        super("info", "Print info about this Odood project.");
        this.add(new Flag(null, "json", "Print output in json format"));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        auto info = project.getInfo();

        if (args.flag("json")) {
            auto json = info.toJSON();
            json.toJSON(true).writeln;
        } else {
            info.toString.writeln;
        }
    }
}
