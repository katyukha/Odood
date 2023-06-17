/// Database simple wrapper that provides utility methods applied to database
module odood.lib.odoo.db;

private import std.logger;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import dpq.connection;

private import odood.lib.project: Project;
private import odood.utils.addons.addon: OdooAddon;
private import odood.exception: OdoodException;


/** This struct represents single Odoo database, and allows to run SQL
  * queries and SQL scripts for this database
  **/
package(odood.lib) struct OdooDatabase {
    private const Project _project;
    private const string _dbname;
    private Connection _connection;

    this(in Project project, in string dbname) {
        _project = project;
        _dbname = dbname;

        auto odoo_conf = _project.getOdooConfig;

        auto conn_host = odoo_conf["options"].hasKey("db_host") ?
            odoo_conf["options"].getKey("db_host") : "localhost";
        auto conn_port = odoo_conf["options"].hasKey("db_port") ?
            odoo_conf["options"].getKey("db_port") : "5432";
        auto conn_user = odoo_conf["options"].hasKey("db_user") ?
            odoo_conf["options"].getKey("db_user") : "odoo";
        auto conn_password = odoo_conf["options"].hasKey("db_password") ?
            odoo_conf["options"].getKey("db_password") : "odoo";

        string conn_str = "dbname='%s'".format(dbname);
        if (conn_host != "False" && conn_host != "None")
            conn_str ~= " host='%s'".format(conn_host);
        if (conn_port != "False" && conn_port != "None")
            conn_str ~= " port='%s'".format(conn_port);
        if (conn_user != "False" && conn_user != "None")
            conn_str ~= " user='%s'".format(conn_user);
        if (conn_password != "False" && conn_password != "None")
            conn_str ~= " password='%s'".format(conn_password);

        _connection = Connection(conn_str);
    }

    /** Return dpq connection to database
      **/
    auto connection() {
        return _connection;
    }

    /** Close connection
      **/
    void close() {
        _connection.close();
    }

    /** Run SQL script for specific database.
      *
      * Note, that this method allows to execut only one query.
      * If you need to run multiple queries at single call,
      * then you can use runSQLScript method.
      *
      * Note, that this method does not check if database exists
      *
      * Params:
      *     query = SQL query to run (possibly with parameters
      *     no_commit = If we need to commit tranasaction or not
      *     params = variadic parameters for query
      **/
    auto runSQLQuery(T...)(
            in string query,
            in bool no_commit,
            T params) {
        import dpq.query;
        import dpq.result;
        import dpq.exception;

        _connection.begin();  // Start new transaction
        Result res;
        try {
            res = Query(_connection, query).run(params);
        } catch (DPQException e) {
            // Rollback in case of any error
            errorf("SQL query thrown error %s!\nQuery:\n%s", e.msg, query);
            _connection.rollback();
            throw e;
        }
        if (no_commit) {
            warningf("Rollback, because 'no_commit' option supplied!");
            _connection.rollback();
        } else {
            _connection.commit();
        }
        return res;
    }

    /// ditto
    auto runSQLQuery(in string query) {
        return runSQLQuery(query, false);
    }

    /** Exec SQL. Supports to run multiple SQL statements,
      * and do not return value
      *
      * Params:
      *     query = SQL query to run (possibly with parameters
      *     no_commit = If we need to commit tranasaction or not
      **/
    void runSQLScript(
            in string query,
            in bool no_commit=false) {
        import dpq.result;
        import dpq.exception;

        _connection.begin();  // Start new transaction
        Result res;
        try {
            _connection.exec(query);
        } catch (DPQException e) {
            // Rollback in case of any error
            errorf("SQL query thrown error %s!\nQuery:\n%s", e.msg, query);
            _connection.rollback();
            throw e;
        }
        if (no_commit) {
            warningf("Rollback, because 'no_commit' option supplied!");
            _connection.rollback();
        } else {
            _connection.commit();
        }
    }


    /** Run SQL script for specific database
      **/
    void runSQLScript(
            in Path script_path,
            in bool no_commit=false) {
        import dpq.query;
        import dpq.result;
        import dpq.exception;
        import std.datetime.stopwatch;

        enforce!OdoodException(
            script_path.exists,
            "SQL script %s does not exists!".format(script_path));

        infof("Running SQL script %s for databse %s ...", script_path, _dbname);
        auto sw = StopWatch(AutoStart.yes);
        runSQLScript(script_path.readFileText, no_commit);
        sw.stop();
        infof(
            "SQL script %s for database %s completed in %s.",
            script_path, _dbname, sw.peek);
    }

    /** Check if database contains demo data.
      **/
    const(bool) hasDemoData() {
        auto res = runSQLQuery(
            "SELECT EXISTS (" ~
            "    SELECT 1 FROM ir_module_module " ~
            "    WHERE state = 'installed' " ~
            "      AND name = 'base' " ~
            "      AND demo = True " ~
            ")",
            false);
        return res.get(0, 0).as!bool.get;
    }

    /** Check if specified module installed on database
      **/
    const(bool) isAddonInstalled(in string addon_name) {
        auto res = runSQLQuery(
            "SELECT EXISTS (" ~
            "    SELECT 1" ~
            "    FROM ir_module_module" ~
            "    WHERE state = 'installed' AND name = $1" ~
            ")",
            false,
            addon_name);
        return res.get(0, 0).as!bool.get;
    }

    /// ditto
    const(bool) isAddonInstalled(in OdooAddon addon) {
        return isAddonInstalled(addon.name);
    }

    /** Stun database (disable cron jobs and mail servers)
      **/
    void stunDb() {
        infof(
            "Disabling cron jobs and mail servers on database %s...", _dbname);
        runSQLScript(
            "UPDATE fetchmail_server SET active=False;
             UPDATE ir_mail_server SET active=False;
             UPDATE ir_cron SET active=False;");
        infof("Cron jobs and mail servers for database %s disabled!", _dbname);
    }
}
