module odood.cli.commands.status;

private import std.stdio: writeln;
private import std.format: format;
private import std.exception: enforce;

private import colored;
private import thepath: Path;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.utils.odoo.serie: OdooSerie;


immutable string TMPL_CURRENT_PROJECT_STATUS = "
Current project:

    Project root: %s
    Project config: %s

    Odoo version: %s
    Odoo branch: %s

    Server status: %s
    Server url: %s
";


class CommandStatus: OdoodCommand {
    this() {
        super("status", "Show the project status.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        writeln(
            TMPL_CURRENT_PROJECT_STATUS.format(
                project.project_root.toString.blue,
                project.config_path.toString.blue,
                project.odoo.serie.toString.green,
                project.odoo.branch.green,
                project.server.isRunning ? "Running".green : "Stopped".red,
                project.server.getConfigHTTP.url.lightBlue,
            )
        );
    }
}


