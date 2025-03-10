/// Database simple wrapper that provides utility methods applied to database
module odood.lib.odoo.db;

private import std.logger;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import peque: Connection;

private import odood.lib.odoo.config;
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

        auto db_conf = _project.parseOdooDatabaseConfig;

        string[string] db_params = [
            "dbname": dbname,
        ];
        if (db_conf.host)
            db_params["host"] = db_conf.host;
        if (db_conf.port)
            db_params["port"] = db_conf.port;
        if (db_conf.user)
            db_params["user"] = db_conf.user;
        if (db_conf.password)
            db_params["password"] = db_conf.password;

        _connection = Connection(db_params);
    }

    /** Return dpq connection to database
      **/
    auto connection() {
        return _connection;
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

        import peque.exception;
        import peque: Result;

        _connection.begin();  // Start new transaction
        Result res;
        try {
            res = _connection.execParams(query, params);
        } catch (PequeException e) {
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
        import peque.exception;

        _connection.begin();  // Start new transaction
        try {
            _connection.exec(query);
        } catch (PequeException e) {
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
        return res[0][0].get!bool;
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
        return res[0][0].get!bool;
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
