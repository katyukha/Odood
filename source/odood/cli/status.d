module odood.cli.status;

private import std.stdio;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.command: OdoodCommand;
private import odood.lib.project: Project, ProjectConfig;
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
        auto project = new Project();

        auto is_running = project.isServerRunning();

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
                project.config.project_root,
                project.config_path,
                project.config.odoo_serie,
                project.config.odoo_branch,
                project.isServerRunning ? "Running" : "Stopped",
                "http://%s:%s".format(http_host, http_port),
            )
        );
    }
}


