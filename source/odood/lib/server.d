/// Contains functions to run odoo server
module odood.lib.server;

private import core.time;
private import core.sys.posix.sys.types: pid_t;

private static import std.process;
private import std.process: ProcessPipes;
private import std.logger;
private import std.string: empty;
private import std.exception: enforce;
private import std.conv: to;
private import std.format: format;
private import std.typecons: Nullable, nullable;

private import thepath: Path;

private import odood.lib.project.config: ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.log: OdooLogProcessor, OdooLogRecord;
private import odood.lib.exception: OdoodException;
private import odood.lib.utils: isProcessRunning;

class ServerException : OdoodException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

class ServerAlreadyRuningException : OdoodException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}


/** Wrapper struct to manage odoo server
  **/
struct OdooServer {
    private const ProjectConfig _config;

    // Struct to implement iterator (range) over log records captured
    // during server ran.
    private struct OdooLogPipe {
        // TODO: May be it have sense to merge this struct with LogProcessor
        private:
            ProcessPipes _pipes;
            OdooLogProcessor _log_processor;
            bool _is_closed;
            Nullable!OdooLogRecord _log_record;
            int _exit_code; 

            void tryReadLogRecordIfNeeded() {
                if (!_log_record.isNull)
                    // We already have log record in buffer, thus
                    // there is no need to read new record.
                    return;

                while (_log_record.isNull && !_is_closed) {
                    string input = _pipes.stderr.readln();
                    if (!input.empty)
                        _log_processor.feedInput(input);
                    else {
                        // It seems that file is close, thus we have to
                        // wait the child process.
                        _exit_code = std.process.wait(_pipes.pid);       
                        _is_closed = true;
                        _log_processor.close();
                    }
                   _log_record = _log_processor.consumeRecord();
                }
            }

            this(ref ProcessPipes pipes) {
                _pipes = pipes;
            }
        public:
            /** This method have to be called to ensure that
              * the child process is existed and properly awaited by
              * parent process, to avoid zombies.
              * In case, if this struct used as range and completely
              * consumed, then it is not required to call this method.
              **/
            int close() {
                if (!_is_closed) {
                    _exit_code = std.process.wait(_pipes.pid);
                }
                return _exit_code;
            }

            /** Return exit code of the process managed by this pipe
              **/
            @property int exit_code() const {
                return _exit_code;
            }

            @property bool empty() {
                tryReadLogRecordIfNeeded();
                return _log_record.isNull;
            }

            @property OdooLogRecord front() {
                tryReadLogRecordIfNeeded();
                return _log_record.get;
            }

            void popFront() {
                tryReadLogRecordIfNeeded();
                _log_record.nullify;
            }
    }

    @disable this();

    /** Construct new server wrapper for this project
      **/
    this(in ProjectConfig config) {
        _config = config;
    }

    /// Get name of odoo server script, depending on odoo serie
    @property string scriptName() const {
        if (_config.odoo_serie >= OdooSerie(11)) {
            return "odoo";
        } else if (_config.odoo_serie == OdooSerie(10)) {
            return "odoo-bin";
        } else if (_config.odoo_serie >= OdooSerie(8)) {
            return "odoo.py";
        } else {
            // Versions older than 8.0
            return "openerp-server";
        }
    }

    /// Get path to the odoo server script to run
    @property Path scriptPath() const {
        return _config.venv.path.join("bin", scriptName());
    }

    /** Get PID of running Odoo Process
      * Returns:
      *    - PID of process running
      *    - -1 if no pid file located
      *    - -2 if process specified in pid file is not running
      **/
    pid_t getPid() const {
        if (_config.odoo_pid_file.exists) {
            auto pid = _config.odoo_pid_file.readFileText.to!pid_t;
            if (isProcessRunning(pid))
                return pid;
            return -2;
        }
        return -1;
    }

    /** Spawn the Odoo server
      *
      **/
    pid_t spawn(bool detach=false) const {
        import std.process: Config;

        enforce!ServerAlreadyRuningException(
            !isRunning,
            "Server already running!");

        const(string[string]) env=[
            "OPENERP_SERVER": _config.odoo_conf.toString,
            "ODOO_RC": _config.odoo_conf.toString,
        ];
        Config process_conf = Config.none;
        if (detach)
            process_conf |= Config.detached;

        info("Starting odoo server...");

        // TODO: move this to virtualenv logic?
        auto server_opts = [
            "--pidfile=%s".format(_config.odoo_pid_file),
        ];
        if (detach)
            server_opts ~= ["--logfile=%s".format(_config.log_file)];

        auto pid = std.process.spawnProcess(
            [
                _config.venv.path.join("bin", "run-in-venv").toString,
                scriptPath.toString,
            ] ~ server_opts,
            env,
            process_conf,
            _config.project_root.toString);
        infof("Odoo server is started. PID: %s", pid.osHandle);
        if (!detach)
            std.process.wait(pid);
        return pid.osHandle;
    }

    /** Run the odoo server with provided options, and pip log output
      * Returns:
      *     Iterator over log entries produced by this call to the server.
      **/
    auto pipeServerLog(string[] options...) const {
        import std.process: Config, Redirect;

        enforce!ServerAlreadyRuningException(
            !isRunning,
            "Server already running!");

        // TODO: Make separate method to get environment for odoo server
        const(string[string]) env=[
            "OPENERP_SERVER": _config.odoo_conf.toString,
            "ODOO_RC": _config.odoo_conf.toString,
        ];
        Config process_conf = Config.none;

        tracef("Starting odoo server (pipe logs) with args %s", options);

        auto server_pipes = std.process.pipeProcess(
            [
                _config.venv.path.join("bin", "run-in-venv").toString,
                scriptPath.toString,
            ] ~ options,
            Redirect.all,
            env,
            process_conf,
            _config.project_root.toString);

        return OdooLogPipe(server_pipes);
    }

    auto run(in string[] options...) const {
        const(string[string]) env=[
            "OPENERP_SERVER": _config.odoo_conf.toString,
            "ODOO_RC": _config.odoo_conf.toString,
        ];
        _config.venv.run(scriptPath, options, _config.project_root, env);
    }

    auto runE(in string[] options...) const {
        const(string[string]) env=[
            "OPENERP_SERVER": _config.odoo_conf.toString,
            "ODOO_RC": _config.odoo_conf.toString,
        ];
        _config.venv.runE(scriptPath, options, _config.project_root, env);
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
