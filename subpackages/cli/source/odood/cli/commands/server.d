module odood.cli.commands.server;

private import core.time;
private import std.logger;
private import std.exception: enforce;
private import std.algorithm.searching: canFind, startsWith;

private import thepath: Path;
private import theprocess: Process;
private import darkcommand;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.project: Project;
private import odood.project.server: DEFAULT_START_TIMEOUT;


class CommandServerRun: OdoodCommand {
    bool ignoreRunning;
    bool waitPg;
    long waitPgTimeout = 60;

    this() {
        super("run", "Run the server.");
        this.addFlag!(ignoreRunning)(
            "", "ignore-running",
            "Ignore running Odoo instance. (Do not check/create pidfile).");
        this.addFlag!(waitPg)(
            "", "wait-pg",
            "Wait for PostgreSQL to be ready before starting the server.");
        this.addOption!(waitPgTimeout)(
            "", "wait-pg-timeout",
            "Maximum time to wait for PostgreSQL in seconds.")
            .defaultValue(60L);
    }

    override int execute() {
        auto project = Project.loadProject;
        auto runner = project.server.getServerRunner();

        runner.addArgs(argsRest);

        if (ignoreRunning) {
            if (!argsRest.canFind!((e) => e.startsWith("--pidfile")))
                runner.addArgs("--pidfile=");
        } else {
            enforce!OdoodCLIException(
                !project.server.isRunning,
                "Odoo server already running!");
        }

        if (waitPg) {
            auto pg_timeout = waitPgTimeout.seconds;
            infof("Waiting for PostgreSQL...");
            enforce!OdoodCLIException(
                project.server.waitForPostgres(pg_timeout),
                "PostgreSQL did not become available within the timeout.");
            infof("PostgreSQL is ready.");
        }

        debug tracef("Running Odoo: %s", runner);
        runner.execv;
        return 0;
    }
}


class CommandServerStart: OdoodCommand {
    long timeout;

    this() {
        super("start", "Run the server in background.");
        this.addOption!(timeout)(
            "t", "timeout",
            "Timeout to wait while server starts (in seconds).")
            .defaultValue(DEFAULT_START_TIMEOUT.total!"seconds");
    }

    override int execute() {
        auto project = Project.loadProject;
        project.server.start(timeout.seconds);
        return 0;
    }
}


class CommandServerStatus: OdoodCommand {
    this() {
        super("status", "Check if server is running");
    }

    override int execute() {
        import std.stdio;
        auto project = Project.loadProject;
        if (project.server.isRunning)
            writeln("The server is running");
        else
            writeln("The server is stopped");
        return 0;
    }
}


class CommandServerStop: OdoodCommand {
    this() {
        super("stop", "Stop the server");
    }

    override int execute() {
        auto project = Project.loadProject;
        project.server.stop();
        return 0;
    }
}


class CommandServerRestart: OdoodCommand {
    long timeout;

    this() {
        super("restart", "Restart the server running in background.");
        this.addOption!(timeout)(
            "t", "timeout",
            "Timeout to wait while server starts (in seconds).")
            .defaultValue(DEFAULT_START_TIMEOUT.total!"seconds");
    }

    override int execute() {
        auto project = Project.loadProject;

        if (project.server.isRunning)
            project.server.stop();

        project.server.start(timeout.seconds);
        return 0;
    }
}


class CommandServerBrowse: OdoodCommand {

    this() {
        super("browse", "Open odoo in browser");
    }

    override int execute() {
        import std.process;
        auto project = Project.loadProject;
        if (!project.server.isRunning)
            project.server.start;

        auto url = project.server.getConfigHTTP.url;
        infof("Opening %s in browse....", url);
        std.process.browse(url);
        return 0;
    }
}


class CommandServerLogView: OdoodCommand {
    this() {
        super("log", "View server logs.");
    }

    override int execute() {
        auto project = Project.loadProject;
        tracef("Viewing logfile: %s", project.odoo.logfile.toString);
        Process("less").withArgs(
            "+G",
            "--",
            project.odoo.logfile.toString
        ).execv;
        return 0;
    }
}


class CommandServerHealthcheck: OdoodCommand {
    long timeout = 10;

    this() {
        super("healthcheck",
            "Check if the Odoo HTTP server is healthy.\n" ~
            "Exits 0 if healthy, 1 if not.\n");
        this.addOption!(timeout)(
            "t", "timeout",
            "HTTP request timeout in seconds.")
            .defaultValue(10L);
    }

    override int execute() {
        auto project = Project.loadProject;

        if (project.server.healthcheck(timeout.seconds))
            infof("Odoo server is healthy.");
        else
            throw new OdoodCLIException("Odoo server is not healthy!");
        return 0;
    }
}


class CommandServerWaitPg: OdoodCommand {
    long timeout = 60;
    long interval = 2;

    this() {
        super("wait-pg", "Wait for PostgreSQL to become available.");
        this.addOption!(timeout)(
            "t", "timeout",
            "Maximum time to wait in seconds.")
            .defaultValue(60L);
        this.addOption!(interval)(
            "", "interval",
            "Time between connection attempts in seconds.")
            .defaultValue(2L);
    }

    override int execute() {
        auto project = Project.loadProject;

        infof("Waiting for PostgreSQL...");
        enforce!OdoodCLIException(
            project.server.waitForPostgres(timeout.seconds, interval.seconds),
            "PostgreSQL did not become available within the timeout.");
        infof("PostgreSQL is ready.");
        return 0;
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
