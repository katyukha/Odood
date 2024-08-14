module odood.cli.commands.server;

private import std.logger;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import theprocess: Process;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.utils.odoo.serie: OdooSerie;


class CommandServerRun: OdoodCommand {
    this() {
        super("run", "Run the server.");
        this.add(new Flag("d", "detach", "Run the server in background."));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        project.server.spawn(args.flag("detach"));
    }

}


class CommandServerStart: OdoodCommand {
    this() {
        super("start", "Run the server in background.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        project.server.start;
    }

}


class CommandServerStatus: OdoodCommand {
    this() {
        super("status", "Check if server is running");
    }

    public override void execute(ProgramArgs args) {
        import std.stdio;
        auto project = Project.loadProject;
        if (project.server.isRunning) {
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
        auto project = Project.loadProject;
        project.server.stop();
    }
}


class CommandServerRestart: OdoodCommand {
    this() {
        super("restart", "Restart the server running in background.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        if (project.server.isRunning)
            project.server.stop();

        project.server.start;
    }

}


class CommandServerBrowse: OdoodCommand {

    this() {
        super("browse", "Open odoo in browser");
    }

    public override void execute(ProgramArgs args) {
        import std.process;
        auto project = Project.loadProject;
        if (!project.server.isRunning)
            project.server.start;

        auto odoo_conf = project.getOdooConfig;

        /** Get option with default value
          **/
        string get_option(
                in string name,
                lazy string default_val) {
            if (odoo_conf["options"].hasKey(name))
                return odoo_conf["options"].getKey(name);
            return default_val;
        }

        string url = "http://%s:%s/".format(
            get_option(
                "http_interface",
                get_option(
                    "xmlrpc_interface", "localhost")),
            get_option(
                "http_port",
                get_option(
                    "xmlrpc_port", "8069"))
        );
        infof("Opening %s in browse....", url);
        std.process.browse(url);
    }

}


class CommandServerLogView: OdoodCommand {
    this() {
        super("log", "View server logs.");
    }

    public override void execute(ProgramArgs args) {
        import std.process;
        auto project = Project.loadProject;
        tracef("Viewing logfile: %s", project.odoo.logfile.toString);
        Process("less").withArgs(project.odoo.logfile.toString).execv;
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
        this.add(new CommandServerBrowse());
        this.add(new CommandServerLogView());
    }
}

