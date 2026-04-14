/// Contains functions to run odoo server
module odood.lib.server.server;

private import core.time;
private import core.sys.posix.sys.types: pid_t;
private import core.thread: Thread;

private static import std.process;
private import std.logger;
private import std.exception: enforce;
private import std.conv: to;
private import std.format: format;
private import std.string: join, strip;
private import std.algorithm.iteration: map;

private import thepath: Path;
private import theprocess: Process, isProcessRunning;

private import odood.lib.project: Project, ProjectServerSupervisor;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.exception: OdoodException;
private import odood.lib.server.exception;
private import odood.lib.odoo.config: getConfVal, readOdooConfig;
private import odood.lib.server.log_pipe;
private import odood.lib.odoo.log: OdooLogRecord, OdooLogProcessor;

immutable auto DEFAULT_START_TIMEOUT = 8.seconds;


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
    this(in Project project, in bool test_mode=false) pure {
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

    /// Get path to server configuration file for this server instance
    @safe pure auto getConfigPath() const {
        if (_test_mode)
            return _project.odoo.testconfigfile;
        else
            return _project.odoo.configfile;
    }

    /// Get server configuration
    auto getConfig() const {
        return getConfigPath.readOdooConfig;
    }

    /// Get HTTP url for the server
    auto getConfigHTTP() const {
        const struct ServerHTTPInfo {
            string host;
            uint port;
            string url;
        }

        auto config = getConfig;

        string host = config.getConfVal(
            _project.odoo.serie >= 11 ? "http_interface" : "xmlrpc_interface",
            "127.0.0.1");
        string port = config.getConfVal(
            _project.odoo.serie >= 11 ? "http_port" : "xmlrpc_port",
            "8069");

        return ServerHTTPInfo(
            host: host,
            port: port.to!uint,
            url: "http://%s:%s".format(host, port),
        );
    }

    /** Get PID of running Odoo Process
      * Returns:
      *    - PID of process running
      *    - -1 if no pid file located
      *    - -2 if process specified in pid file is not running
      **/
    pid_t getPid() const {
        final switch(_project.odoo.server_supervisor) {
            case ProjectServerSupervisor.Odood, ProjectServerSupervisor.InitScript:
                if (_project.odoo.pidfile.exists) {
                    auto pid = _project.odoo.pidfile.readFileText.strip.to!pid_t;
                    if (isProcessRunning(pid))
                        return pid;
                    return -2;
                }
                return -1;
            case ProjectServerSupervisor.Systemd:
                return Process("systemctl")
                    .withArgs("show", "--property=MainPID", "--value", "odoo")
                    .withFlag(std.process.Config.stderrPassThrough)
                    .execute
                    .ensureOk(true)
                    .output.strip.to!pid_t;
        }
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

        string odoo_rc_env_var = _project.odoo.serie > 10 ? "ODOO_RC" : "OPENERP_SERVER";
        res[odoo_rc_env_var] = getConfigPath.toString;

        // TODO: Add ability to parse .env files and forward environment variables to Odoo process
        //       This will allow to run Odoo in docker containers and locally in similar way.
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
            .inWorkDir(_project.project_root)
            .withEnv(getServerEnv);

        if (_project.odoo.server_user)
            runner.setUser(_project.odoo.server_user);

        if (coverage.enable) {
            enforce!OdoodException(
                _project.venv.path.join("bin", "coverage").exists,
                "Coverage not installed. Please, install it via 'odood venv install-py-packages coverage' to continue.");
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
        // TODO: Add ability to handle coverage settings and other odoo options
        enforce!ServerAlreadyRuningException(
            !isRunning,
            "Server already running!");

        enforce!OdoodException(
            !detach || _project.odoo.server_supervisor == ProjectServerSupervisor.Odood,
            "Cannot run Odoo server in background, because it is not managed byt Odood.");

        auto runner = getServerRunner(
            "--pidfile=%s".format(_project.odoo.pidfile));
        if (detach) {
            runner.setFlag(std.process.Config.detached);
            if (!_project.odoo.logfile.isNull)
                runner.addArgs("--logfile=%s".format(_project.odoo.logfile.get));
        }

        if (_project.odoo.pidfile.exists) {
            // At this point it is already checked that server is not running,
            // thus it is safe to delete stale pid file.
            tracef("Removing pidfile %s before server starts...", _project.odoo.pidfile);
            _project.odoo.pidfile.remove();
        }

        info("Starting odoo server...");
        auto pid = runner.spawn();

        infof("Odoo server is started. PID: %s", pid.osHandle);
        if (!detach)
            std.process.wait(pid);
        return pid.osHandle;
    }

    /** Run the odoo server with provided options, and pipe log output
      * Returns:
      *     Iterator over log entries produced by this call to the server.
      **/
    auto pipeServerLog(in CoverageOptions coverage, in string[] options...) const {
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
      * Params:
      *    wait_timeout = how long to wait if server starts.
      *        If set to Duration.zero (default), then do not wait for server startup.
      *        Also, if wait_timeout is specified, but system will not start
      *        during that time, then error will be raised.
      **/
    void start(in Duration wait_timeout=DEFAULT_START_TIMEOUT) const {
        final switch(_project.odoo.server_supervisor) {
            case ProjectServerSupervisor.Odood:
                this.spawn(true);
                break;
            case ProjectServerSupervisor.InitScript:
                Process("/etc/init.d/odoo")
                    .withArgs("start")
                    .execute
                    .ensureOk(true);
                break;
            case ProjectServerSupervisor.Systemd:
                Process("service")
                    .withArgs("odoo", "start")
                    .execute
                    .ensureOk(true);
                break;
        }
        // Here we check if server was really started, by checking server PID
        if (wait_timeout != Duration.zero) {
            for(long i=0; i < wait_timeout.total!"seconds"; i++)
                if (isRunning)
                    // If server is running, there is no need to wait more time
                    return;
                else
                    // If server is not running yet, sleep for one second.
                    Thread.sleep(1.seconds);
            // Ensure server was started. We reached wait limit,
            // and expect that server was started.
            // If it is not started yet, then it is error.
            enforce!OdoodException(
                isRunning,
                "Cannot start Odoo!");
        }

    }

    /** Stop the Odoo server via Odood
      *
      **/
    void stopOdoodServer() const {
        import core.sys.posix.signal: kill, SIGTERM;
        import core.stdc.errno: errno, ESRCH;
        import std.exception: ErrnoException;

        info("Stopping odoo server...");
        auto odoo_pid = getPid();
        enforce!ServerAlreadyRuningException(
            odoo_pid > 0,
            "Server is not running!");

        for(ubyte i=0; isProcessRunning(odoo_pid) && i < 15; i++) {
            int res = kill(odoo_pid, SIGTERM);

            // Wait 1 second, before next check
            Thread.sleep(1.seconds);

            if (res == -1 && errno == ESRCH) {
                // Process killed successfully
                if (_project.odoo.pidfile.exists) {
                    tracef("Removing pidfile %s after server stopped...", _project.odoo.pidfile);
                    _project.odoo.pidfile.remove();
                }
                break;
            }
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
                    .ensureOk(true);
                break;
            case ProjectServerSupervisor.Systemd:
                Process("service")
                    .withArgs("odoo", "stop")
                    .execute
                    .ensureOk(true);
                break;
        }
    }

    /** Check if the Odoo HTTP server is responding and healthy.
      *
      * For Odoo 14+: uses /web/health, expects HTTP 200.
      * For older Odoo: uses /web/, accepts any HTTP response below 500
      *     (200 or 302 both indicate Odoo is up).
      *
      * Params:
      *     timeout = HTTP request timeout. Default is 10 seconds.
      *
      * Returns:
      *     true if the server is healthy, false otherwise.
      **/
    bool healthcheck(in Duration timeout = 10.seconds) const {
        import requests: Request;

        // /web/health exists from Odoo 14; for older versions /web/ responds
        // with 200 or 302 when the server is up.
        string path = _project.odoo.serie >= OdooSerie(14)
            ? "/web/health" : "/web/";
        string url = "%s%s".format(getConfigHTTP.url, path);

        try {
            auto request = Request();
            request.timeout = timeout;
            auto response = request.get(url);
            if (_project.odoo.serie >= OdooSerie(14))
                return response.code == 200;
            else
                return response.code < 500;
        } catch (Exception e) {
            tracef("Healthcheck failed: %s", e.msg);
            return false;
        }
    }


    /** Wait for PostgreSQL to become available.
      *
      * Tries to connect to the PostgreSQL server configured in odoo.conf.
      * Retries until connected or timeout expires.
      *
      * Params:
      *     timeout  = maximum time to wait. Default 60 seconds.
      *     interval = time between connection attempts. Default 2 seconds.
      *
      * Returns:
      *     true if PostgreSQL became available within timeout, false otherwise.
      **/
    bool waitForPostgres(
            in Duration timeout = 60.seconds,
            in Duration interval = 2.seconds) const {
        import core.time: MonoTime;
        import peque.exception: PequeException;
        import odood.lib.odoo.db_utils: openPgConnection;

        auto deadline = MonoTime.currTime + timeout;
        while (MonoTime.currTime < deadline) {
            try {
                _project.openPgConnection("postgres");
                return true;
            } catch (PequeException e) {
                tracef("PostgreSQL not ready yet: %s", e.msg);
                Thread.sleep(interval);
            }
        }
        return false;
    }


    /** Run delegate and gather Odoo errors happened while delegate was running.
      **/
    auto catchOdooErrors(TE=OdoodException)(void delegate () dg) const {
        import std.stdio: File;

        struct Result {
            bool has_error = false;
            Exception error = null;
            OdooLogRecord[] log;
        }
        Result result;

        File log_file;
        if (!_project.odoo.logfile.isNull && _project.odoo.logfile.get.exists)
            // Open file only if file exists
            log_file = _project.odoo.logfile.get.openFile("rt");

        scope(exit) log_file.close();

        if (!_project.odoo.logfile.isNull && !log_file.isOpen && _project.odoo.logfile.get.exists)
            // If file is not opened but exists, open it.
            // This is needed to correctly compute starting point
            // for tracking log messages happened during operation (dg)
            log_file.open(_project.odoo.logfile.get.toString, "rt");

        auto log_start = log_file.isOpen ? log_file.size() : 0;

        try {
            // Try to apply delegate
            dg();
        } catch (TE e) {
            result.error = e;
            result.has_error = true;

            if (!_project.odoo.logfile.isNull && !log_file.isOpen && _project.odoo.logfile.get.exists)
                // If file is not opened but exists, open it.
                // This is needed to be able to read log messages
                // happeded during execution of dg delegate
                log_file.open(_project.odoo.logfile.get.toString, "rt");

            // Search for errors in logfile.
            if (log_file.isOpen && log_file.size > log_start) {
                log_file.seek(log_start);
                foreach(log_line; OdooLogProcessor(log_file))
                    if (log_line.isError)
                        result.log ~= log_line;
            }
        }

        return result;
    }
}
