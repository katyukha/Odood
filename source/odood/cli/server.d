module odood.cli.server;

private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.command: OdoodCommand;
private import odood.lib.project: Project, ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;
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


class CommandServerStart: OdoodCommand {
    this() {
        super("start", "Run the server in background.");
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        project.serverRun(true);
    }

}


class CommandServerStatus: OdoodCommand {
    this() {
        super("status", "Check if server is running");
    }

    public override void execute(ProgramArgs args) {
        import std.stdio;
        auto project = new Project();
        if (project.isServerRunning) {
            writeln("The server is running");
        } else {
            writeln("The server is stopped");
        }
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


class CommandServerRestart: OdoodCommand {
    this() {
        super("restart", "Restart the server running in background.");
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        project.serverStop();
        project.serverRun(true);
    }

}


class CommandServer: OdoodCommand {
    this() {
        super("server", "Server management commands.");
        this.add(new CommandServerRun());
        this.add(new CommandServerStart());
        this.add(new CommandServerStatus());
        this.add(new CommandServerStop());
        this.add(new CommandServerRestart());
    }
}

