/// Contains functions to run odoo server
module odood.lib.server.server;

private import core.time;
private import core.sys.posix.sys.types: pid_t;

private static import std.process;
private import std.logger;
private import std.exception: enforce;
private import std.conv: to;
private import std.format: format;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.exception: OdoodException;
private import odood.lib.utils: isProcessRunning;
private import odood.lib.server.exception;
private import odood.lib.server.log_pipe;


package(odood) struct CoverageOptions {
    Path[] include;
    Path[] source;
    bool enable;

    @disable this();

    this(in bool enable) {
        this.enable = enable;
    }
}


/** Wrapper struct to manage odoo server
  **/
struct OdooServer {
    private const Project _project;

    @disable this();

    /** Construct new server wrapper for this project
      **/
    this(in Project project) {
        _project = project;
    }

    /// Get name of odoo server script, depending on odoo serie
    @property @safe pure string scriptName() const {
        if (_project.odoo.serie >= OdooSerie(11)) {
            return "odoo";
        } else if (_project.odoo.serie == OdooSerie(10)) {
            return "odoo-bin";
        } else if (_project.odoo.serie >= OdooSerie(8)) {
            return "odoo.py";
        } else {
            // Versions older than 8.0
            return "openerp-server";
        }
    }

    /// Get path to the odoo server script to run
    @property @safe pure Path scriptPath() const {
        return _project.venv.path.join("bin", scriptName());
    }

    /** Get PID of running Odoo Process
      * Returns:
      *    - PID of process running
      *    - -1 if no pid file located
      *    - -2 if process specified in pid file is not running
      **/
    pid_t getPid() const {
        if (_project.odoo.pidfile.exists) {
            auto pid = _project.odoo.pidfile.readFileText.to!pid_t;
            if (isProcessRunning(pid))
                return pid;
            return -2;
        }
        return -1;
    }

    private const(string[string]) getServerEnv() const {
        return [
            "OPENERP_SERVER": _project.odoo.configfile.toString,
            "ODOO_RC": _project.odoo.configfile.toString,
        ];
    }

    /** Prepare command to be used to run the server
      * with or without coverage.
      **/
    private string[] getServerCmd(
            in CoverageOptions coverage,
            in string[] options...) const {
        import std.string: join;
        import std.algorithm: map;
        string[] cmd = [
            _project.venv.path.join("bin", "run-in-venv").toString];

        if (coverage.enable) {
            string source = coverage.source.map!(p => p.toString).join(",");
            cmd ~= [
                "coverage",
                "run",
                "--parallel-mode",
                "--source=%s".format(source),
                "--omit=*/__openerp__.py,*/__manifest__.py",
                //"--include=%s/*".format(Path.current.toString),
            ];
        }
        cmd ~= [scriptPath.toString];
        cmd ~= options;
        return cmd;
    }

    /** Prepare server command combined with server options
      *
      * Params:
      *     options = odoo server options
      **/
    private @safe pure string[] getServerCmd(in string[] options) const {
        return [
            _project.venv.path.join("bin", "run-in-venv").toString,
            scriptPath.toString,
        ] ~ options;
    }

    /** Spawn the Odoo server
      *
      **/
    pid_t spawn(bool detach=false) const {
        import std.process: Config;

        enforce!ServerAlreadyRuningException(
            !isRunning,
            "Server already running!");

        Config process_conf = Config.none;
        if (detach)
            process_conf |= Config.detached;

        info("Starting odoo server...");

        // TODO: move this to virtualenv logic?
        auto server_opts = [
            "--pidfile=%s".format(_project.odoo.pidfile),
        ];
        if (detach)
            server_opts ~= ["--logfile=%s".format(_project.odoo.logfile)];

        auto pid = std.process.spawnProcess(
            getServerCmd(server_opts),
            getServerEnv,
            process_conf,
            _project.project_root.toString);
        infof("Odoo server is started. PID: %s", pid.osHandle);
        if (!detach)
            std.process.wait(pid);
        return pid.osHandle;
    }

    /** Run the odoo server with provided options, and pip log output
      * Returns:
      *     Iterator over log entries produced by this call to the server.
      **/
    auto pipeServerLog(in CoverageOptions coverage, string[] options...) const {
        import std.process: Config, Redirect;
        import std.string: join;

        enforce!ServerAlreadyRuningException(
            !isRunning,
            "Server already running!");

        Config process_conf = Config.none;

        tracef(
            "Starting odoo server (pipe logs, coverage=%s) cmd: %s", 
            coverage, getServerCmd(coverage, options).join(" "));

        // TODO: If there is no --logfile option in options list,
        //       then, we have to manually specify '--logfile=' option,
        //       to enforce output to stdout, even if there is other option
        //       used in config.

        auto server_pipes = std.process.pipeProcess(
            getServerCmd(coverage, options),
            Redirect.all,
            getServerEnv,
            process_conf,
            Path.current.toString);  // _project.project_root.toString);

        return OdooLogPipe(server_pipes);
    }

    /// ditto
    auto pipeServerLog(string[] options...) const {
        return pipeServerLog(CoverageOptions(false), options);
    }

    auto run(in string[] options...) const {
        _project.venv.run(scriptPath, options, _project.project_root, getServerEnv);
    }

    auto runE(in string[] options...) const {
        _project.venv.runE(scriptPath, options, _project.project_root, getServerEnv);
    }

    /** Check if the Odoo server is running or not
      *
      **/
    bool isRunning() const {
        auto odoo_pid = getPid();
        if (odoo_pid <= 0) {
            return false;
        }

        return isProcessRunning(odoo_pid);
    }

    /** Stop the Odoo server
      *
      **/
    void stop() const {
        import core.sys.posix.signal: kill, SIGTERM;
        import core.stdc.errno;
        import core.thread: Thread;
        import std.exception: ErrnoException;

        info("Stopping odoo server...");
        auto odoo_pid = getPid();
        enforce!ServerAlreadyRuningException(
            odoo_pid > 0,
            "Server is not running!");

        for(ubyte i=0; isProcessRunning(odoo_pid) && i < 10; i++) {
            int res = kill(odoo_pid, SIGTERM);

            // Wait 1 second, before next check
            Thread.sleep(1.seconds);

            if (res == -1 && errno == ESRCH)
                break; // Process killed
            if (res == -1) {
                throw new ErrnoException("Cannot kill odoo");
            }
        }
        info("Server stopped.");
    }
}
