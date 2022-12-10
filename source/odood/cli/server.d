module odood.cli.server;

private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.command: OdoodCommand;
private import odood.lib.project: Project, ProjectConfig;
private import odood.lib.odoo_serie: OdooSerie;
private import odood.lib.exception: OdoodException;


class CommandServerRun: OdoodCommand {
    this() {
        super("run", "Run the server.");
        this.add(new Flag("d", "detach", "Run the server in background."));
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        project.serverRun(args.flag("detach"));
    }

}


class CommandServerStop: OdoodCommand {
    this() {
        super("stop", "Stop the server");
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        project.serverStop();
    }
}


class CommandServer: OdoodCommand {
    this() {
        super("server", "Server management commands.");
        this.add(new CommandServerRun());
        this.add(new CommandServerStop());
    }
}

