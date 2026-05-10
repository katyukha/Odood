/// Print info about current Odood project
module odood.cli.commands.info;

private import std.json: toJSON;
private import std.stdio: writeln;

private import darkcommand;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.project.info: getInfo;


class CommandInfo: OdoodCommand {
    bool json;

    this() {
        super("info", "Print info about this Odood project.");
        this.addFlag!(json)("", "json", "Print output in json format");
    }

    override int execute() {
        auto project = Project.loadProject;
        auto info = project.getInfo();

        if (json) {
            auto j = info.toJSON();
            j.toJSON(true).writeln;
        } else {
            info.toString.writeln;
        }
        return 0;
    }
}
