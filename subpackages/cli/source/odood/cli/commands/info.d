/// Print info about current Odood project
module odood.cli.commands.info;

private import std.stdio: writeln;

private import darkcommand;

private import odood.cli.core: OdoodCommand;
private import odood.cli.utils: printJSON;
private import odood.lib.project: Project;
private import odood.lib.project.info: getInfo;


class CommandInfo: OdoodCommand {
    bool json;

    this() {
        super("info", "Print info about this Odood project.");
        this.addFlag!(json)("", "json", "Print output in JSON format.");
    }

    override int execute() {
        auto project = Project.loadProject;
        auto info = project.getInfo();

        if (json) {
            printJSON(info.toJSON());
        } else {
            info.toString.writeln;
        }
        return 0;
    }
}
