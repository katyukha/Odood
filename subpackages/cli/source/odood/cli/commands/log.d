module odood.cli.commands.log;

private import std.logger;
private import theprocess;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;


class CommandLogView: OdoodCommand {
    this() {
        super("log", "View log.");
    }

    public override void execute(ProgramArgs args) {
        import std.process;
        auto project = Project.loadProject;
        tracef("Viewing logfile: %s", project.odoo.logfile.toString);
        Process("less").withArgs(project.odoo.logfile.toString).execv;
    }
}
