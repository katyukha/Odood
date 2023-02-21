module odood.cli.commands.status;

private import std.stdio;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.exception: OdoodException;


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

        auto is_running = project.server.isRunning();

        auto odoo_config = project.getOdooConfig();

        string http_host = "localhost";
        if (odoo_config["options"].hasKey("http_interface"))
            http_host = odoo_config["options"].getKey("http_interface");
        else if (odoo_config["options"].hasKey("xmlrpc_interface"))
            http_host = odoo_config["options"].getKey("xmlrpc_interface");

        string http_port = "8069";
        if (odoo_config["options"].hasKey("http_port"))
            http_port = odoo_config["options"].getKey("http_port");
        else if (odoo_config["options"].hasKey("xmlrpc_port"))
            http_port = odoo_config["options"].getKey("xmlrpc_port");

        writeln(
            TMPL_CURRENT_PROJECT_STATUS.format(
                project.project_root,
                project.config_path,
                project.odoo.serie,
                project.odoo.branch,
                project.server.isRunning ? "Running" : "Stopped",
                "http://%s:%s".format(http_host, http_port),
            )
        );
    }
}


