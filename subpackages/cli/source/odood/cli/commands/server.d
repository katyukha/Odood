module odood.cli.commands.server;

private import core.time;
private import std.logger;
private import std.conv: to;
private import std.format: format;
private import std.exception: enforce;
private import std.algorithm.searching: canFind, startsWith;

private import thepath: Path;
private import theprocess: Process;
private import commandr: Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.project: Project;
private import odood.utils.odoo.serie: OdooSerie;


class CommandServerRun: OdoodCommand {
    this() {
        super("run", "Run the server.");
        this.add(new Flag(
            null, "ignore-running", "Ingore running Odoo instance. (Do not check/create pidfile)."));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        auto runner = project.server.getServerRunner();

        runner.addArgs(args.argsRest);

        if (args.flag("ignore-running")) {
            // if no --pidfile option specified, enforce no pidfile.
            // This is needed to avoid messing up pid of running app.
            if (!args.argsRest.canFind!((e) => e.startsWith("--pidfile")))
                runner.addArgs("--pidfile=");
        } else {
            enforce!OdoodCLIException(
                !project.server.isRunning,
                "Odoo server already running!");
        }

        debug tracef("Running Odoo: %s", runner);
        runner.execv;
    }
}


class CommandServerStart: OdoodCommand {
    this() {
        super("start", "Run the server in background.");
        this.add(new Option(
            "t", "timeout", "Timeout to wait while server starts"));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        auto timeout = args.option("timeout") ?
            args.option("timeout").to!long.seconds :
            Duration.zero;
        project.server.start(timeout);
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
        this.add(new Option(
            "t", "timeout", "Timeout to wait while server starts"));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto timeout = args.option("timeout") ?
            args.option("timeout").to!long.seconds :
            Duration.zero;

        if (project.server.isRunning)
            project.server.stop();

        project.server.start(timeout);
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

