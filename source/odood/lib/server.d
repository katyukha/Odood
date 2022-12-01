/// Contains functions to run odoo server
module odood.lib.server;

private static import std.process;
private import core.sys.posix.sys.types: pid_t;
private import std.exception: enforce;
private import std.conv: to;
private import std.format: format;

private import thepath: Path;

private import odood.lib.project_config: ProjectConfig;
private import odood.lib.odoo_serie: OdooSerie;
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



/// Get name of odoo server script, depending on odoo serie
string getServerScriptName(in ProjectConfig config) {
    if (config.odoo_serie >= OdooSerie(11)) {
        return "odoo";
    } else if (config.odoo_serie == OdooSerie(10)) {
        return "odoo-bin";
    } else if (config.odoo_serie >= OdooSerie(8)) {
        return "odoo.py";
    } else {
        // Versions older than 8.0
        return "openerp-server";
    }
}


/// Get path to the odoo server script to run
Path getServerScriptPath(in ProjectConfig config) {
    return config.venv_dir.join("bin", getServerScriptName(config));
}

/** Get PID of running Odoo Process
  * Params:
  *    config = Project configuration to get PID for
  * Returns:
  *    - PID of process running
  *    - -1 if no pid file located
  *    - -2 if process specified in pid file is not running
  **/
pid_t getServerPid(in ProjectConfig config) {
    if (config.odoo_pid_file.exists) {
        auto pid = config.odoo_pid_file.readFileText.to!pid_t;
        if (isProcessRunning(pid))
            return pid;
        return -2;
    }
    return -1;
}


/** Spawn the Odoo server
  *
  **/
pid_t spawnServer(in ProjectConfig config, bool detach=false) {
    import std.process: Config;

    auto odoo_pid = getServerPid(config);
    enforce!ServerAlreadyRuningException(
        odoo_pid <= 0,
        "Server already running!");

    const(string[string]) env=[
        "OPENERP_SERVER": config.odoo_conf.toString,
        "ODOO_RC": config.odoo_conf.toString,
    ];
    Config process_conf = Config.none;
    if (detach)
        process_conf |= Config.detached;

    auto pid = std.process.spawnProcess(
        [getServerScriptPath(config).toString,
         "--pidfile=%s".format(config.odoo_pid_file)],
        env,
        process_conf,
        config.root_dir.toString);
    odoo_pid = pid.osHandle;
    if (!detach)
        std.process.wait(pid);
    return odoo_pid;
}

/** Stop the Odoo server
  *
  **/
void stopServer(in ProjectConfig config) {
    import core.time;
    import core.sys.posix.signal: kill, SIGTERM;
    import core.stdc.errno;
    import core.thread: Thread;
    import std.exception: ErrnoException;

    auto odoo_pid = getServerPid(config);
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
}
