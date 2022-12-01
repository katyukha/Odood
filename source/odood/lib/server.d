/// Contains functions to run odoo server
module odood.lib.server;

private static import std.process;
private import core.sys.posix.sys.types: pid_t;
private import std.conv: to;

private import odood.lib.project_config: ProjectConfig;
private import odood.lib.odoo_serie: OdooSerie;
private import odood.lib.utils: isProcessRunning;


/// Get name of odoo server script, depending on odoo serie
string getServerScript(in ProjectConfig config) {
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

