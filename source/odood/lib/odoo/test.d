/** Module that defines test runner, that is responsible
  * for running tests of odoo modules
  **/
module odood.lib.odoo.test;

private import std.logger;
private import std.string: join, empty;
private import std.format: format;
private import std.algorithm: map;
private import std.exception: enforce;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.lodoo: LOdoo;
private import odood.lib.odoo.log: OdooLogRecord;
private import odood.lib.odoo.addon: OdooAddon;
private import odood.lib.addons.manager: AddonManager;
private import odood.lib.server: OdooServer, CoverageOptions;
private import odood.lib.exception: OdoodException;
private import odood.lib.utils: generateRandomString;

private immutable ODOO_TEST_HTTP_PORT=8269;
private immutable ODOO_TEST_LONGPOLLING_PORT=8272;


private struct OdooTestResult {
    private bool _success;
    private OdooLogRecord[] _log_records;

    /** Check if test was successfull
      *
      **/
    pure const(bool) success() const {
        return _success;
    }

    /** Get list of all log records
      *
      **/
    pure const(OdooLogRecord[]) logRecords() const {
        return _log_records;
    }

    /** Set the test result failed
      *
      **/
    package pure void setFailed() {
        _success = false;
    }

    /** Set the test result successful
      *
      **/
    pure void setSuccess() {
        _success = true;
    }

    /** Add log record to test result
      *
      **/
    package pure void addLogRecord(in OdooLogRecord record) {
        _log_records ~= record;
    }

    /** Return range on log records, each represent warning
      *
      **/
    auto warnings() const {
        import std.algorithm;
        return _log_records.filter!(r => r.log_level == "WARNING");
    }

    /** Return range over log records that return only errors
      *
      **/
    auto errors() const {
        import std.algorithm;
        return _log_records.filter!(
            r => r.log_level == "ERROR" || r.log_level == "CRITICAL");
    }
}


struct OdooTestRunner {

    private const Project _project;
    private const LOdoo _lodoo;
    private const OdooServer _server;

    // TODO: Create separate struct to handle AddonsLists
    private const(OdooAddon)[] _addons;  // Addons to run tests for

    private string _test_db_name;
    private bool _temporary_db;
    private Path _log_file;
    private void delegate(in ref OdooLogRecord rec) _log_handler;

    // Coverage configuration
    private bool _coverage;

    this(in Project project) {
        _project = project;
        _lodoo = LOdoo(_project, _project.odoo.configfile);
        _server = OdooServer(_project);
        _temporary_db = false;
    }

    private void getOrCreateTestDb() {
        if (!_test_db_name)
            setDatabaseName(
                "odood%s-odood-test".format(_project.odoo.serie.major));
        if (!_lodoo.databaseExists(_test_db_name))
            _lodoo.databaseCreate(_test_db_name, true);
    }

    private void logToFile(in ref OdooLogRecord log_record) {
        _log_file.appendFile(
            "%s %s %s %s %s: %s\n".format(
                log_record.date, log_record.process_id, log_record.log_level,
                log_record.db, log_record.logger, log_record.msg));
    }

    /** Set name of database to run test on
      **/
    auto ref setDatabaseName(in string dbname) {
        _test_db_name = dbname;
        _log_file = _project.directories.log.join("test.%s.log".format(_test_db_name));

        tracef(
            "Setting dbname=%s and logfile=%s for test runner",
            _test_db_name, _log_file);

        return this;
    }

    /** Configure test runner to automatically create temporary database
      * with randomized name and to drop created database after test completed.
      **/
    auto ref useTemporaryDatabase() {
        tracef(
            "Using temporary database. " ~
            "It will be removed after tests finished");
        _temporary_db = true;
        return setDatabaseName(
            "odood%s-test-%s".format(
                _project.odoo.serie.major, generateRandomString(8)));
    }

    /** Enable Coverage
      **/
    auto ref setCoverage(in bool coverage) {
        _coverage = coverage;
        return this;
    }

    auto getCoverageOptions() {
        CoverageOptions res = CoverageOptions(_coverage);
        foreach(addon; _addons)
            res.source ~= addon.path;
        return res;
    }

    /// Add new module to test run
    auto ref addModule(in ref OdooAddon addon) {
        tracef("Adding %s addon to test runner...", addon.name);
        _addons ~= [addon];
        return this;
    }

    /// ditto
    auto ref addModule(in string addon_name) {
        auto addon = _project.addons.getByName(addon_name);
        enforce!OdoodException(
            !addon.isNull,
            "Cannot find addon %s!".format(addon_name));
        return addModule(addon.get);
    }

    /** Register handler that will be called to process each log record
      * captured by this test runner.
      **/
    auto ref registerLogHandler(
            scope void delegate(in ref OdooLogRecord) handler) {
        _log_handler = handler;
        return this;
    }

    /** Take clean up actions before test finished
      **/
    void cleanUp() {
        if (_temporary_db && _lodoo.databaseExists(_test_db_name)) {
            _lodoo.databaseDrop(_test_db_name);
        }
    }

    /** Run tests
      **/
    auto run() {
        enforce!OdoodException(
            _addons.length > 0,
            "No addons specified for test");
        getOrCreateTestDb();

        OdooTestResult result;

        auto opt_http_port = _project.odoo.serie > OdooSerie(10) ?
                "--http-port=%s".format(ODOO_TEST_HTTP_PORT) :
                "--xmlrpc-port=%s".format(ODOO_TEST_HTTP_PORT);

        auto init_res =_server.pipeServerLog(
            getCoverageOptions(),
            [
                "--init=%s".format(_addons.map!(a => a.name).join(",")),
                "--log-level=warn",
                "--logfile=",
                "--stop-after-init",
                "--workers=0",
                "--longpolling-port=%s".format(ODOO_TEST_LONGPOLLING_PORT),
                opt_http_port,
                "--database=%s".format(_test_db_name),
            ]
        );
        foreach(log_record; init_res) {
            logToFile(log_record);
            if (_log_handler)
                _log_handler(log_record);
            result.addLogRecord(log_record);
        }

        if(init_res.close != 0) {
            result.setFailed();
            cleanUp();
            return result;
        }

        auto update_res =_server.pipeServerLog(
            getCoverageOptions(),
            [
                "--update=%s".format(_addons.map!(a => a.name).join(",")),
                "--log-level=info",
                "--logfile=",
                "--stop-after-init",
                "--workers=0",
                "--test-enable",
                "--database=%s".format(_test_db_name),
            ]);
        foreach(log_record; update_res) {
            logToFile(log_record);
            if (_log_handler)
                _log_handler(log_record);

            result.addLogRecord(log_record);
        }

        if (update_res.close != 0) {
            result.setFailed();
            cleanUp();
            return result;
        }

        if (!result.errors.empty)
            result.setFailed();
        else
            result.setSuccess();

        cleanUp();
        return result;
    }
}
