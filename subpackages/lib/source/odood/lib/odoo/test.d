/** Module that defines test runner, that is responsible
  * for running tests of odoo modules
  **/
module odood.lib.odoo.test;

private import std.logger;
private import std.regex;
private import std.string: join, empty;
private import std.format: format;
private import std.algorithm: map;
private import std.exception: enforce;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.lodoo: LOdoo;
private import odood.lib.odoo.log: OdooLogRecord;
private import odood.lib.addons.addon: OdooAddon;
private import odood.lib.addons.manager: AddonManager;
private import odood.lib.server: OdooServer, CoverageOptions;
private import odood.lib.exception: OdoodException;
private import odood.lib.utils: generateRandomString;
private static import signal = odood.lib.signal;

private immutable ODOO_TEST_HTTP_PORT=8269;
private immutable ODOO_TEST_LONGPOLLING_PORT=8272;

// Regular expressions to check for errors
private immutable auto RE_ERROR_CHECKS = [
    ctRegex!(`At least one test failed`),
    ctRegex!(`invalid module names, ignored`),
    ctRegex!(`no access rules, consider adding one`),
    ctRegex!(`OperationalError: FATAL`),
    ctRegex!(`Comparing apples and oranges`),
    ctRegex!(`Module [a-zA-Z0-9_]\+ demo data failed to install, installed without demo data`),
    ctRegex!(`[a-zA-Z0-9\\._]\+.create() includes unknown fields`),
    ctRegex!(`[a-zA-Z0-9\\._]\+.write() includes unknown fields`),
    ctRegex!(`The group [a-zA-Z0-9\\._]\+ defined in view [a-zA-Z0-9\\._]\+ [a-z]\+ does not exist!`),
    ctRegex!(`[a-zA-Z0-9\\._]\+: inconsistent 'compute_sudo' for computed fields`),
    ctRegex!(`Module .+ demo data failed to install, installed without demo data`),
];

private immutable auto RE_SAFE_WARNINGS = [
    ctRegex!(`Two fields \(.+\) of .+\(\) have the same label`),
];

private struct OdooTestResult {
    private bool _success;
    private bool _cancelled;
    private string _cancel_reason;
    private const(OdooLogRecord)[] _log_records;

    /** Check if test was successfull
      *
      **/
    pure const(bool) success() const {
        return _success;
    }

    /** Check if test was cancelled
      *
      **/
    pure const(bool) cancelled() const {
        return _cancelled;
    }

    /** Get the cancel reason
      *
      **/
    pure string cancelReason() const {
        return _cancel_reason;
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

    /** Set the test result status cancelled
      * This will automatically make test failed
      **/
    package pure void setCancelled(in string reason) {
        _cancelled = true;
        _cancel_reason = reason;
        setFailed();
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
    package pure void addLogRecord(in ref OdooLogRecord record) {
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
        return _log_records.filter!((r) {
            if (r.log_level == "ERROR" || r.log_level == "CRITICAL")
                return true;

            foreach(check; RE_ERROR_CHECKS)
               if (r.msg.matchFirst(check))
                   return true;

            return false;
        });
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

    // Optionaly we can ignore non important warnings
    private bool _ignore_safe_warnings;

    this(in Project project) {
        _project = project;
        _lodoo = LOdoo(_project, _project.odoo.testconfigfile);
        _server = OdooServer(
                _project,
                true,  // Enable test mode
        );
        _temporary_db = false;
    }

    private void getOrCreateTestDb() {
        if (!_test_db_name)
            setDatabaseName(
                "odood%s-odood-test".format(_project.odoo.serie.major));
        if (!_lodoo.databaseExists(_test_db_name)) {
            _lodoo.databaseCreate(_test_db_name, true);
        }
    }

    private void logToFile(in ref OdooLogRecord log_record) {
        _log_file.appendFile(log_record.full_str);
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
        if (!addon.getManifest.installable) {
            warningf("Addon %s is not installable. Skipping", addon.name);
            return this;
        }

        tracef("Adding %s addon to test runner...", addon.name);
        _addons ~= [addon];
        return this;
    }

    /// ditto
    auto ref addModule(in string addon_name_or_path) {
        auto addon = _project.addons.getByString(addon_name_or_path);
        enforce!OdoodException(
            !addon.isNull,
            "Cannot find addon %s!".format(addon_name_or_path));
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

    /** Ignore safe warnings
      **/
    auto ref ignoreSafeWarnings(in bool flag=true) {
        _ignore_safe_warnings = flag;
    }

    /** Get coma-separated list of modules to run tests for.
      **/
    string getModuleList() {
        return _addons.map!(a => a.name).join(",");
    }

    /** Take clean up actions before test finished
      **/
    void cleanUp() {
        if (_temporary_db && _lodoo.databaseExists(_test_db_name)) {
            _lodoo.databaseDrop(_test_db_name);
        }
    }

    /** Check if we need to ignore the record or not
      * Returns: true if record have to be processed and
      *          false if record have to be ignored.
      **/
    bool filterLogRecord(in ref OdooLogRecord record) {
        if (this._ignore_safe_warnings && record.log_level == "WARNING") {
            foreach(check; RE_SAFE_WARNINGS)
                if (record.msg.matchFirst(check)) {
                    return false;
                }
        }
        return true;
    }

    /** Run tests
      **/
    auto runImpl() {
        enforce!OdoodException(
            _addons.length > 0,
            "No addons specified for test");
        getOrCreateTestDb();

        OdooTestResult result;

        auto opt_http_port = _project.odoo.serie > OdooSerie(10) ?
                "--http-port=%s".format(ODOO_TEST_HTTP_PORT) :
                "--xmlrpc-port=%s".format(ODOO_TEST_HTTP_PORT);

        signal.initSigIntHandling();
        scope(exit) signal.deinitSigIntHandling();

        infof("Installing modules before test...");
        auto init_res =_server.pipeServerLog(
            getCoverageOptions(),
            [
                "--init=%s".format(getModuleList),
                "--log-level=warn",
                "--stop-after-init",
                "--workers=0",
                "--longpolling-port=%s".format(ODOO_TEST_LONGPOLLING_PORT),
                opt_http_port,
                "--database=%s".format(_test_db_name),
            ]
        );
        foreach(ref log_record; init_res) {
            logToFile(log_record);

            if (!filterLogRecord(log_record))
                continue;

            if (_log_handler)
                _log_handler(log_record);
            result.addLogRecord(log_record);

            if (signal.interrupted) {
                warningf("Canceling test because of Keyboard Interrupt");
                result.setCancelled("Keyboard interrupt");
                cleanUp();
                init_res.kill();
                return result;
            }
        }

        if(init_res.wait != 0) {
            result.setFailed();
            cleanUp();
            return result;
        }

        infof("Running tests for modules: %s", getModuleList);
        auto update_res =_server.pipeServerLog(
            getCoverageOptions(),
            [
                "--update=%s".format(getModuleList),
                "--log-level=info",
                "--stop-after-init",
                "--workers=0",
                "--test-enable",
                "--database=%s".format(_test_db_name),
            ]);
        foreach(ref log_record; update_res) {
            logToFile(log_record);

            if (!filterLogRecord(log_record))
                continue;

            if (_log_handler)
                _log_handler(log_record);

            result.addLogRecord(log_record);

            if (signal.interrupted) {
                warningf("Canceling test because of Keyboard Interrupt");
                result.setCancelled("Keyboard interrupt");
                cleanUp();
                update_res.kill();
                return result;
            }
        }

        if (update_res.wait != 0) {
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

    auto run() {
        try {
            return runImpl();
        } catch (OdoodException e) {
            cleanUp();
            throw e;
        }
    }
}
