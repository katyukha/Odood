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
private import odood.lib.server: DEFAULT_START_TIMEOUT;


class CommandServerRun: OdoodCommand {
    this() {
        super("run", "Run the server.");
        this.add(new Flag(
            null, "ignore-running", "Ingore running Odoo instance. (Do not check/create pidfile)."));
        this.add(new Flag(
            null, "wait-pg",
            "Wait for PostgreSQL to be ready before starting the server."));
        this.add(new Option(
            null, "wait-pg-timeout",
            "Maximum time to wait for PostgreSQL in seconds.")
            .defaultValue("60"));
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

        if (args.flag("wait-pg")) {
            auto pg_timeout = args.option("wait-pg-timeout").to!long.seconds;
            infof("Waiting for PostgreSQL...");
            enforce!OdoodCLIException(
                project.server.waitForPostgres(pg_timeout),
                "PostgreSQL did not become available within the timeout.");
            infof("PostgreSQL is ready.");
        }

        debug tracef("Running Odoo: %s", runner);
        runner.execv;
    }
}


class CommandServerStart: OdoodCommand {
    this() {
        super("start", "Run the server in background.");
        this.add(new Option(
            "t", "timeout", "Timeout to wait while server starts (in seconds).").defaultValue(DEFAULT_START_TIMEOUT.total!"seconds".to!string));
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
            "t", "timeout", "Timeout to wait while server starts (in seconds).").defaultValue(DEFAULT_START_TIMEOUT.total!"seconds".to!string));
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

        auto url = project.server.getConfigHTTP.url;
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
        Process("less").withArgs(
            "+G",
            "--",
            project.odoo.logfile.toString
        ).execv;
    }
}


class CommandServerHealthcheck: OdoodCommand {
    this() {
        super("healthcheck",
            "Check if the Odoo HTTP server is healthy.\n" ~
            "Exits 0 if healthy, 1 if not.\n");
        this.add(new Option(
            "t", "timeout",
            "HTTP request timeout in seconds.")
            .defaultValue("10"));
    }

    public override void execute(ProgramArgs args) {
        import std.stdio: writeln;
        import core.time: seconds;

        auto project = Project.loadProject;
        auto timeout = args.option("timeout").to!long.seconds;

        if (project.server.healthcheck(timeout))
            infof("Odoo server is healthy.");
        else
            throw new OdoodCLIException("Odoo server is not healthy!");
    }
}


class CommandServerWaitPg: OdoodCommand {
    this() {
        super("wait-pg", "Wait for PostgreSQL to become available.");
        this.add(new Option(
            "t", "timeout",
            "Maximum time to wait in seconds.")
            .defaultValue("60"));
        this.add(new Option(
            null, "interval",
            "Time between connection attempts in seconds.")
            .defaultValue("2"));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        auto timeout = args.option("timeout").to!long.seconds;
        auto interval = args.option("interval").to!long.seconds;

        infof("Waiting for PostgreSQL...");
        enforce!OdoodCLIException(
            project.server.waitForPostgres(timeout, interval),
            "PostgreSQL did not become available within the timeout.");
        infof("PostgreSQL is ready.");
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
        this.add(new CommandServerHealthcheck());
        this.add(new CommandServerWaitPg());
    }
}

