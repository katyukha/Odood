/// Contains functions to run odoo server
module odood.lib.server.server;

private import core.time;
private import core.sys.posix.sys.types: pid_t;

private static import std.process;
private import std.logger;
private import std.exception: enforce;
private import std.conv: to;
private import std.format: format;
private import std.string: join, strip;
private import std.algorithm: map;

private import thepath: Path;

private import odood.lib.project: Project, ProjectServerSupervisor;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.exception: OdoodException;
private import odood.utils: isProcessRunning;
private import odood.lib.server.exception;
private import odood.lib.server.log_pipe;
private import theprocess: Process;


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
    private const bool _test_mode;  // TODO: May be use path to conf file instead?

    @disable this();

    /** Construct new server wrapper for this project
      **/
    this(in Project project, in bool test_mode=false) {
        _project = project;
        _test_mode = test_mode;
    }

    /// Return current test mode of the server
    @safe pure nothrow const(bool) testMode() const {
        return _test_mode;
    }

    /// Get name of odoo server script, depending on odoo serie
    @safe pure string scriptName() const {
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
    @safe pure Path scriptPath() const {
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
            auto pid = _project.odoo.pidfile.readFileText.strip.to!pid_t;
            if (isProcessRunning(pid))
                return pid;
            return -2;
        }
        return -1;
    }

    /** Get environment variables to apply when running Odoo server.
      *
      * Params:
      *     env = extra environment variables to apply.
      **/
    private const(string[string]) getServerEnv(in string[string] env=null) const {
        string[string] res;
        if (env)
            foreach(k, v; env) res[k] = v;

        if (_test_mode) {
            res["OPENERP_SERVER"] = _project.odoo.testconfigfile.toString;
            res["ODOO_RC"] = _project.odoo.testconfigfile.toString;
        } else {
            res["OPENERP_SERVER"] = _project.odoo.configfile.toString;
            res["ODOO_RC"] = _project.odoo.configfile.toString;
        }
        return res;
    }

    /** Prepare preconfigured server runner,
      * optionally with provided coverage settings
      *
      * Params:
      *     coverage = coverage options
      *     options = odoo server options
      **/
    auto getServerRunner(
            in CoverageOptions coverage,
            in string[] options...) const {
        auto runner = _project.venv.runner()
            .inWorkDir(_project.project_root.toString)
            .withEnv(getServerEnv);

        if (_project.odoo.server_user)
            runner.setUser(_project.odoo.server_user);

        if (coverage.enable) {
            // Run server with coverage mode
            runner.addArgs(
                _project.venv.path.join("bin", "coverage").toString,
                "run",
                "--parallel-mode",
                "--omit=*/__openerp__.py,*/__manifest__.py",
                // TODO: Add --data-file option. possibly store it in CoverageOptions
            );
            if (coverage.source.length > 0)
                runner.addArgs(
                    "--source=%s".format(
                        coverage.source.map!(p => p.toString).join(",")),
                );
            if (coverage.include.length > 0)
                runner.addArgs(
                    "--include=%s".format(
                        coverage.include.map!(
                            p => p.toString ~ "/*").join(",")),
                );
        }

        runner.addArgs(scriptPath.toString);
        runner.addArgs(options);
        return runner;
    }

    /// ditto
    auto getServerRunner(in string[] options...) const {
        return getServerRunner(CoverageOptions(false), options);
    }

    /** Spawn the Odoo server
      *
      * Params:
      *     detach = if set, then run server in background
      **/
    pid_t spawn(bool detach=false) const {
        import std.process: Config;

        enforce!ServerAlreadyRuningException(
            !isRunning,
            "Server already running!");

        enforce!OdoodException(
            !detach || _project.odoo.server_supervisor == ProjectServerSupervisor.Odood,
            "Cannot run Odoo server in beckground, because it is not managed byt Odood.");

        auto runner = getServerRunner(
            "--pidfile=%s".format(_project.odoo.pidfile));
        if (detach) {
            runner.setFlag(Config.detached);
            runner.addArgs("--logfile=%s".format(_project.odoo.logfile));
        }

        info("Starting odoo server...");
        auto pid = runner.spawn();

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
        auto runner = getServerRunner(coverage, options)
            .inWorkDir(Path.current); // Run in current directory to make coverage work.

        tracef(
            "Starting odoo server (pipe logs, coverage=%s, test_mode=%s) cmd: %s",
            coverage.enable, _test_mode, runner);

        auto server_pipes = runner.pipe(std.process.Redirect.all);

        return OdooLogPipe(server_pipes);
    }

    /// ditto
    auto pipeServerLog(string[] options...) const {
        return pipeServerLog(CoverageOptions(false), options);
    }

    /** Run server with provided options.
      *
      * Params:
      *     options = list of options to pass to the server
      *     env = extra environment variables to pass to the server
      **/
    auto run(in string[] options, in string[string] env=null) const {
        auto res = _project.venv.run(
            scriptPath,
            options,
            _project.project_root,
            getServerEnv(env));

        return res;
    }

    /// ditto
    auto run(in string[] options...) const {
        return run(options, null);
    }

    /** Run server with provided options
      *
      * In case of non-zero exit code error will be raised.
      *
      * Params:
      *     options = list of options to pass to the server
      *     env = extra environment variables to pass to the server
      **/
    auto runE(in string[] options, in string[string] env=null) const {
        auto result = run(options, env).ensureStatus!ServerCommandFailedException(true);
        return result;
    }

    /// ditto
    auto runE(in string[] options...) const {
        return runE(options, null);
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

    /** Start the Odoo server
      *
      **/
    void start() const {
        final switch(_project.odoo.server_supervisor) {
            case ProjectServerSupervisor.Odood:
                this.spawn(true);
                break;
            case ProjectServerSupervisor.InitScript:
                Process("/etc/init.d/odoo")
                    .withArgs("start")
                    .execute
                    .ensureOk();
                break;
        }

    }

    /** Stop the Odoo server via Odood
      *
      **/
    void stopOdoodServer() const {
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


    /** Stop the Odoo server
      *
      **/
    void stop() const {
        final switch(_project.odoo.server_supervisor) {
            case ProjectServerSupervisor.Odood:
                this.stopOdoodServer();
                break;
            case ProjectServerSupervisor.InitScript:
                Process("/etc/init.d/odoo")
                    .withArgs("stop")
                    .execute
                    .ensureOk();
                break;
        }
    }
}
