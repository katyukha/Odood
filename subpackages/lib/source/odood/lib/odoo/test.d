/** Module that defines test runner, that is responsible
  * for running tests of odoo modules
  **/
module odood.lib.odoo.test;

private import std.datetime.stopwatch;

private import std.logger;
private import std.regex;
private import std.string: join, empty, splitLines;
private import std.format: format;
private import std.algorithm: map, filter, canFind;
private import std.exception: enforce;
private import std.typecons: Nullable, nullable;
private import std.conv: to;
private import core.time: dur;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.lib.odoo.config: getConfVal;
private import odood.lib.odoo.lodoo: LOdoo;
private import odood.lib.odoo.log: OdooLogRecord;
private import odood.lib.odoo.db_manager: OdooDatabaseManager;
private import odood.lib.addons.manager: AddonManager;
private import odood.lib.addons.repository: AddonRepository;
private import odood.lib.server: OdooServer, CoverageOptions;
private import odood.lib.server.log_pipe: OdooLogPipe;
private import odood.exception: OdoodException;
private import odood.utils: generateRandomString, getFreePort;
private import odood.utils.addons.addon: OdooAddon;
private import odood.utils.odoo.serie: OdooSerie;



/** Generate name of test database for specified Odood project
  *
  * Params:
  *     project = project to generate name of test database for.
  **/
string generateTestDbName(in Project project) {
    string prefix = project.server.getConfig.getConfVal(
        "db_user", "odood%s".format(project.odoo.serie.major));
    return "%s-odood-test".format(prefix);
}


// Regular expressions to check for errors
private immutable auto RE_ERROR_CHECKS = [
    ctRegex!(`At least one test failed`),
    ctRegex!(`invalid module names, ignored`),
    ctRegex!(`OperationalError: FATAL`),
    ctRegex!(`Comparing apples and oranges`),
    ctRegex!(`Module .+ demo data failed to install, installed without demo data`),
    ctRegex!(`[a-zA-Z0-9\\._]+\.create\(\) includes unknown fields`),
    ctRegex!(`[a-zA-Z0-9\\._]+\.write\(\) includes unknown fields`),
    ctRegex!(`[a-zA-Z0-9\\._]+\.create\(\) with unknown fields`),
    ctRegex!(`[a-zA-Z0-9\\._]+\.write\(\) with unknown fields`),
    ctRegex!(`The group [a-zA-Z0-9\\._]+ defined in view [a-zA-Z0-9\\._]+ [a-z]+ does not exist!?`),
    ctRegex!(`The group [“'”"][a-zA-Z0-9\\._]+[“'”"] defined in view does not exist!?`),
    ctRegex!(`[a-zA-Z0-9\\._]+: inconsistent 'compute_sudo' for computed fields`),
    ctRegex!(`Field [a-zA-Z0-9\\._]+ with unknown comodel_name '[a-zA-Z0-9\\._]+'`),
];

/* Regex for "Unmet dependencies" reports.
 * Treated as an error for normal tests, but ignored for migration tests
 */
private immutable auto RE_UNMET_DEPENDENCIES = ctRegex!(
    `^module [a-zA-Z0-9\\._]+: Unmet dependencies: [a-zA-Z0-9\\._,\s]+`);

unittest {
    import unit_threaded.assertions;

    // RE_ERROR_CHECKS are matched against OdooLogRecord.msg — the message
    // portion extracted from log lines like:
    //   2023-01-02 15:34:26,873 115109 WARNING mydb odoo.modules.loading: <msg>
    // The test inputs below use realistic msg values as they would appear
    // after log parsing.

    bool is_re_error(in string msg) {
        foreach(check; RE_ERROR_CHECKS)
           if (msg.matchFirst(check))
               return true;
        return false;
    }

    // Test each RE_ERROR_CHECKS pattern individually

    // Pattern: "At least one test failed"
    is_re_error("At least one test failed when loading modules").shouldBeTrue;
    is_re_error("At least one test failed").shouldBeTrue;

    // Pattern: "invalid module names, ignored"
    is_re_error("invalid module names, ignored: nonexistent_module ").shouldBeTrue;

    // Pattern: "OperationalError: FATAL"
    is_re_error("OperationalError: FATAL:  password authentication failed for user \"odoo\" ").shouldBeTrue;
    is_re_error("OperationalError: FATAL:  database \"nonexistent\" does not exist ").shouldBeTrue;

    // Pattern: "Comparing apples and oranges"
    is_re_error("Comparing apples and oranges: res.partner(1,) and 'Administrator' ").shouldBeTrue;

    // Pattern: "Module .+ demo data failed to install, installed without demo data"
    is_re_error("Module sale demo data failed to install, installed without demo data ").shouldBeTrue;
    is_re_error("Module generic_request_service demo data failed to install, installed without demo data ").shouldBeTrue;

    // Pattern: ".create() includes unknown fields"
    is_re_error("The model 'res.partner' does not exist. res.partner.create() includes unknown fields: custom_field ").shouldBeTrue;
    is_re_error("sale.order.line.create() includes unknown fields: nonexistent_field ").shouldBeTrue;
    is_re_error("sale.order.line.create() with unknown fields: nonexistent_field ").shouldBeTrue;

    // Pattern: ".write() includes unknown fields"
    is_re_error("res.partner.write() includes unknown fields: missing_field ").shouldBeTrue;
    is_re_error("account.move.line.write() includes unknown fields: bad_column ").shouldBeTrue;
    is_re_error("sale.order.line.write() with unknown fields: nonexistent_field ").shouldBeTrue;

    // Pattern: "The group X defined in view Y ... does not exist!"
    is_re_error("The group base.group_erp_manager defined in view sale.view_order_form edit does not exist!").shouldBeTrue;
    is_re_error("The group sale.group_sale_manager defined in view account.view_move_form invisible does not exist!").shouldBeTrue;
    is_re_error("The group “my_group” defined in view does not exist").shouldBeTrue;
    is_re_error("The group 'my_group' defined in view does not exist").shouldBeTrue;

    // Pattern: "inconsistent 'compute_sudo' for computed fields"
    is_re_error("sale.order: inconsistent 'compute_sudo' for computed fields: amount_total, amount_untaxed ").shouldBeTrue;
    is_re_error("res.partner: inconsistent 'compute_sudo' for computed fields: display_name ").shouldBeTrue;

    // Pattern: "Field X with unknown comodel_name 'Y'"
    is_re_error("Field sale.order.custom_partner_id with unknown comodel_name 'res.custom.partner' ").shouldBeTrue;
    is_re_error("Field generic_request.request.service_id with unknown comodel_name 'generic.service' ").shouldBeTrue;

    // "Unmet dependencies" is NOT in RE_ERROR_CHECKS - it is handled in
    // OdooTestResult.errors (see the dedicated unittest below).
    is_re_error("module mod_a: Unmet dependencies: mod_b").shouldBeFalse;

    // Negative cases: normal operational messages that should NOT match
    is_re_error("Odoo version 16.0 ").shouldBeFalse;
    is_re_error("skip sending email in test mode ").shouldBeFalse;
    is_re_error("Starting TestRequestBase.test_request_can_change_category ... ").shouldBeFalse;
    is_re_error("loading 38 modules... ").shouldBeFalse;
    is_re_error("Module sale loaded in 0.42s, 12 queries ").shouldBeFalse;
    is_re_error("").shouldBeFalse;
}

/// Test RE_SAFE_WARNINGS patterns with realistic log messages
unittest {
    import unit_threaded.assertions;

    bool is_safe_warning(in string msg) {
        foreach(check; RE_SAFE_WARNINGS)
           if (msg.matchFirst(check))
               return true;
        return false;
    }

    // Pattern: "Two fields (X) of Y() have the same label"
    // Based on real log: odoo.test.2.log line 16-17
    is_safe_warning(
        "Two fields (date_closed, closed) of request.request() have the same label: Closed. "
    ).shouldBeTrue;
    is_safe_warning(
        "Two fields (create_uid, created_by_id) of request.request() have the same label: Created by. "
    ).shouldBeTrue;

    // Pattern: "Field X: unknown parameter 'tracking'..."
    is_safe_warning(
        "Field generic_request.request.date_deadline: unknown parameter 'tracking', " ~
        "if this is an actual parameter you may want to override the " ~
        "method _valid_field_parameter on the relevant model in order to allow it"
    ).shouldBeTrue;

    // Non-matching warnings should not be filtered
    is_safe_warning("At least one test failed ").shouldBeFalse;
    is_safe_warning("").shouldBeFalse;
}

/// Test OdooTestResult state management
unittest {
    import unit_threaded.assertions;

    // Test initial state
    OdooTestResult result;
    result.success.shouldBeFalse;
    result.cancelled.shouldBeFalse;
    result.cancelReason.shouldBeNull;
    result.logRecords.length.shouldEqual(0);

    // Test setSuccess
    result.setSuccess();
    result.success.shouldBeTrue;
    result.cancelled.shouldBeFalse;

    // Test setFailed
    result.setFailed();
    result.success.shouldBeFalse;
    result.cancelled.shouldBeFalse;

    // Test setCancelled sets both cancelled and failed
    result.setSuccess();  // reset to success first
    result.success.shouldBeTrue;
    result.setCancelled("Keyboard interrupt");
    result.success.shouldBeFalse;
    result.cancelled.shouldBeTrue;
    result.cancelReason.shouldEqual("Keyboard interrupt");
}

/// Test OdooTestResult log record filtering (warnings/errors)
unittest {
    import std.algorithm: map;
    import std.array: array;
    import unit_threaded.assertions;

    OdooTestResult result;

    // Add various log records
    OdooLogRecord info_rec;
    info_rec.log_level = "INFO";
    info_rec.msg = "Normal info message";
    result.addLogRecord(info_rec);

    OdooLogRecord warn_rec;
    warn_rec.log_level = "WARNING";
    warn_rec.msg = "Some warning";
    result.addLogRecord(warn_rec);

    OdooLogRecord err_rec;
    err_rec.log_level = "ERROR";
    err_rec.msg = "Something failed";
    result.addLogRecord(err_rec);

    OdooLogRecord crit_rec;
    crit_rec.log_level = "CRITICAL";
    crit_rec.msg = "Critical failure";
    result.addLogRecord(crit_rec);

    // A WARNING that matches RE_ERROR_CHECKS (treated as error)
    OdooLogRecord warn_error_rec;
    warn_error_rec.log_level = "WARNING";
    warn_error_rec.msg = "At least one test failed";
    result.addLogRecord(warn_error_rec);

    result.logRecords.length.shouldEqual(5);

    // warnings() should return only WARNING-level records
    auto warnings = result.warnings.array;
    warnings.length.shouldEqual(2);
    warnings[0].msg.shouldEqual("Some warning");
    warnings[1].msg.shouldEqual("At least one test failed");

    // errors() should return ERROR, CRITICAL, and WARNING matching RE_ERROR_CHECKS
    auto errors = result.errors.array;
    errors.length.shouldEqual(3);
    errors.map!(e => e.msg).array.shouldEqual(
        ["Something failed", "Critical failure", "At least one test failed"]);
}

/// Test that unmet-dependency reports are treated as errors for normal tests,
/// but ignored (not failing the run) for migration tests.
unittest {
    import std.array: array;
    import unit_threaded.assertions;

    OdooLogRecord unmet_rec;
    unmet_rec.log_level = "INFO";
    unmet_rec.logger = "odoo.modules.graph";
    unmet_rec.msg = "module mod_a: Unmet dependencies: mod_b";

    // Several coma-separated dependencies are matched too.
    OdooLogRecord unmet_multi_rec;
    unmet_multi_rec.log_level = "INFO";
    unmet_multi_rec.logger = "odoo.modules.graph";
    unmet_multi_rec.msg = "module mod_a: Unmet dependencies: mod_b, mod_c";

    // Normal test: unmet dependency is treated as an error.
    {
        OdooTestResult result;
        result.addLogRecord(unmet_rec);
        result.addLogRecord(unmet_multi_rec);

        result.errors.array.length.shouldEqual(2);
        result.warnings.array.length.shouldEqual(0);
    }

    // Migration test: transient unmet-dependency reports do not fail the run.
    {
        OdooTestResult result;
        result.setMigrationTest(true);
        result.addLogRecord(unmet_rec);
        result.addLogRecord(unmet_multi_rec);

        result.errors.array.length.shouldEqual(0);

        // Unmet dependencies has INFO log level, thus  no warnings
        result.warnings.array.length.shouldEqual(0);
    }

    // Migration test: a real ERROR-level report is still treated as an error.
    {
        OdooTestResult result;
        result.setMigrationTest(true);

        OdooLogRecord err_rec;
        err_rec.log_level = "ERROR";
        err_rec.msg =
            "Some modules have inconsistent states, some dependencies may be missing: ['x']";
        result.addLogRecord(err_rec);

        result.errors.array.length.shouldEqual(1);
        result.warnings.array.length.shouldEqual(0);
    }
}

/// Test OdooTestResult duration tracking
unittest {
    import core.time: seconds;
    import unit_threaded.assertions;

    OdooTestResult result;
    result.setDurationTotal(5.seconds);
    result.setDurationTests(3.seconds);

    result.totalDuration.shouldEqual(5.seconds);
    result.testsDuration.shouldEqual(3.seconds);
}


/* Regular expression, that could be used to list "safe" warnings,
 * that could be optionally ignored in output
 */
private immutable auto RE_SAFE_WARNINGS = [
    ctRegex!(`Two fields \(.+\) of .+\(\) have the same label`),
    ctRegex!(`Field [\w\.]+: unknown parameter 'tracking', if this is an actual parameter you may want to override the method _valid_field_parameter on the relevant model in order to allow it`),
];


// Regular expressions to parse statistics emitted by Odoo's `odoo.tests.stats`
// logger (enabled via `--log-handler=odoo.tests.stats:INFO|DEBUG`).
//
// Summary mode (INFO) emits one record per module:
//     <module>: N tests X.XXs Q queries
//
// Detailed mode (DEBUG) emits a single multi-line record holding entries for
// every module / module.Class / module.Class.method aggregation level:
//     Detailed Tests Report:
//     \t<name>: X.XXs Q queries
//     \t...
//
// Each pattern is matched per line.  The summary pattern is tried first as it
// is the more specific one.  Lines matching neither are ignored (tolerant
// parsing — the message format may vary between Odoo series).
private immutable auto RE_TEST_STAT_SUMMARY = ctRegex!(
    `^\s*(?P<name>\S.*?):\s+(?P<tests>\d+)\s+tests\s+(?P<time>[\d.]+)s\s+(?P<queries>\d+)\s+queries\s*$`);
private immutable auto RE_TEST_STAT_DETAILED = ctRegex!(
    `^\s*(?P<name>\S.*?):\s+(?P<time>[\d.]+)s\s+(?P<queries>\d+)\s+queries\s*$`);


/** Single statistics entry captured from the `odoo.tests.stats` logger.
  *
  * Depending on logger level, `name` may be a module, a module.Class, or a
  * module.Class.method aggregation level.
  **/
struct OdooTestStat {
    /// Name of the entry (module, module.Class or module.Class.method).
    string name;

    /// Wall-clock time spent.
    Duration duration;

    /// Number of SQL queries executed.
    ulong queries;
}


/** Parse test-statistics entries from a single log record.
  *
  * Handles both the summary (one record per module) and detailed (a single
  * multi-line record) output formats of Odoo's `log_stats()`.
  *
  * Params:
  *     rec = log record to parse
  *
  * Returns: array of parsed entries (possibly empty) for records emitted by
  *          the `odoo.tests.stats` logger; empty for any other record.
  **/
private OdooTestStat[] parseTestStats(in OdooLogRecord rec) {
    if (rec.logger != "odoo.tests.stats")
        return [];

    static Duration toDuration(in string seconds) {
        return dur!"msecs"(cast(long)(seconds.to!double * 1000));
    }

    OdooTestStat[] result;
    foreach(line; rec.msg.splitLines) {
        if (auto m = line.matchFirst(RE_TEST_STAT_SUMMARY))
            result ~= OdooTestStat(
                m["name"], toDuration(m["time"]), m["queries"].to!ulong);
        else if (auto m = line.matchFirst(RE_TEST_STAT_DETAILED))
            result ~= OdooTestStat(
                m["name"], toDuration(m["time"]), m["queries"].to!ulong);
    }
    return result;
}

unittest {
    import unit_threaded.assertions;

    OdooLogRecord rec(in string logger, in string msg) {
        OdooLogRecord r;
        r.logger = logger;
        r.msg = msg;
        return r;
    }

    // Records from other loggers are ignored.
    parseTestStats(rec("odoo.modules.loading", "sale: 12 queries")).length.shouldEqual(0);

    // Detailed (DEBUG) report: single multi-line record with the module /
    // module.Class / module.Class.method aggregation levels emitted by Odoo.
    auto detailed = parseTestStats(rec(
        "odoo.tests.stats",
        "Detailed Tests Report:\n" ~
        "\tsale: 3.40s 128 queries\n" ~
        "\tsale.test_sale.TestSale: 1.25s 42 queries\n" ~
        "\tsale.test_sale.TestSale.test_confirm: 1.25s 42 queries\n"));
    detailed.length.shouldEqual(3);
    detailed[2].name.shouldEqual("sale.test_sale.TestSale.test_confirm");
    detailed[2].duration.shouldEqual(dur!"msecs"(1250));
    detailed[2].queries.shouldEqual(42);

    // Summary (INFO): one record per module.
    auto summary = parseTestStats(rec(
        "odoo.tests.stats", "sale: 7 tests 3.40s 128 queries"));
    summary.length.shouldEqual(1);
    summary[0].name.shouldEqual("sale");
    summary[0].duration.shouldEqual(dur!"msecs"(3400));
    summary[0].queries.shouldEqual(128);

    // The report header line (and any other unrecognized content) is ignored.
    parseTestStats(rec("odoo.tests.stats", "Detailed Tests Report:")).length.shouldEqual(0);
}


/** Struct that represents test result
  **/
private struct OdooTestResult {
    private bool _success;
    private bool _cancelled;
    private string _cancel_reason;
    private bool _migration_test;
    private const(OdooLogRecord)[] _log_records;
    private OdooTestStat[] _test_stats;

    private Duration _duration_total;
    private Duration _duration_tests;

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
    package pure void setSuccess() {
        _success = true;
    }

    /** Mark this result as produced by a migration test.
      *
      * Migration tests upgrade and install addons in separate graph passes, so
      * Odoo emits transient "Unmet dependencies" reports that are not real
      * errors here (truly missing dependencies still surface as ERROR-level
      * reports). Thus such reports are ignored for migration tests only.
      **/
    package pure void setMigrationTest(in bool migration_test=true) {
        _migration_test = migration_test;
    }

    /** Add log record to test result
      *
      **/
    package pure void addLogRecord(in OdooLogRecord record) {
        _log_records ~= record;
    }

    /** Add captured test-statistics entry to test result
      *
      **/
    package pure void addTestStat(in OdooTestStat stat) {
        _test_stats ~= stat;
    }

    /** Get list of captured test-statistics entries
      *
      **/
    pure const(OdooTestStat[]) testStats() const {
        return _test_stats;
    }

    /** Set the total duration of test run
      *
      **/
    package pure void setDurationTotal(in Duration dur) {
        _duration_total = dur;
    }

    /** Set the duration of tests for this test run
      *
      **/
    package pure void setDurationTests(in Duration dur) {
        _duration_tests = dur;
    }

    /** Return range on log records, each represent warning
      *
      **/
    auto warnings() const {
        return _log_records.filter!(r => r.log_level == "WARNING");
    }

    /** Return range over log records that return only errors
      *
      **/
    auto errors() const {
        return _log_records.filter!((r) {
            if (r.isError)
                return true;

            // Unmet-dependency reports are errors for normal tests, but
            // ignored for migration tests (see setMigrationTest).
            if (!r.msg.matchFirst(RE_UNMET_DEPENDENCIES).empty)
                return !_migration_test;

            // Try to detect warnings that we treat as errors
            foreach(check; RE_ERROR_CHECKS)
               if (r.msg.matchFirst(check))
                   return true;

            return false;
        });
    }

    /** Return total duration of this test run.
      **/
    auto totalDuration() const { return _duration_total; };

    /** Return duration of tests for this test run.
      **/
    auto testsDuration() const { return _duration_tests; };
}


/** Struct that represents configurable test runner.
  **/
struct OdooTestRunner {
    private const Project _project;
    private const LOdoo _lodoo;
    private const OdooDatabaseManager _databases;
    private const OdooServer _server;

    // TODO: Create separate struct to handle AddonsLists
    private const(OdooAddon)[] _addons;  // Addons to run tests for

    // Additional addons to install before test
    private const(OdooAddon)[] _additional_addons;

    // Database configuration
    private string _test_db_name;
    private bool _temporary_db;
    private bool _db_no_drop;

    // Logging config
    private Path _log_file;
    private void delegate(in OdooLogRecord rec) _log_handler;

    // Coverage configuration
    private bool _coverage;

    // Optionaly we can ignore non important warnings
    private bool _ignore_safe_warnings;

    // Migration tests settings
    private bool _test_migration=false;
    private string _test_migration_start_ref=null;
    private AddonRepository _test_migration_repo;
    private bool _test_migration_use_last_release=false;

    // Populate data before test (useful for migration testing)
    // TODO: Also handle case, when addon is not available on start ref
    // TODO: This works only for Odoo 17 and below.
    // Odoo 18 changed the way population work and it does not have sense now.
    private string[] _populate_models=[];
    private string _populate_size="small";

    // Test tags (--test-tags, Odoo 12.0+)
    private string[] _test_tags;

    // Test statistics collection via odoo.tests.stats logger (Odoo 13.0+)
    private bool _test_stats_enabled=false;
    private bool _test_stats_detailed=false;

    // Other configuration
    private bool _need_install_addons_before_test=true;

    this(in Project project) {
        _project = project;

        // We have to instantiate LOdoo instance that will use
        // test odoo config
        _lodoo = _project.lodoo(true);

        // Instantiate Odoo server in test mode
        _server = _project.server(true);

        // Instantiate database manager in test mode
        _databases = _project.databases(true);

        // By default, do not use temporary database,
        // instead, use default test database
        _temporary_db = false;
    }

    auto test_migration() const { return _test_migration; }
    auto migration_repo() const { return _test_migration_repo; }
    auto migration_start_ref() const { return _test_migration_start_ref; }

    auto need_install_addons_before_test() const { return _need_install_addons_before_test; }

    /** Ensure test database exests, and create it if it does not exists
      **/
    private void getOrCreateTestDb() {
        if (!_test_db_name)
            setDatabaseName(generateTestDbName(_project));
        if (!_lodoo.databaseExists(_test_db_name)) {
            _lodoo.databaseCreate(_test_db_name, true);
        }
    }

    /** Write specified log record to log file linked with this
      * test runner.
      **/
    private void logToFile(in OdooLogRecord log_record) {
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

    /** Enable migration testing
      **/
    auto ref enableMigrationTest() {
        _test_migration = true;
        return this;
    }

    /** Set start git ref (branch, commit, test) for migration test
      **/
    auto ref setMigrationStartRef(in string git_ref) {
        _test_migration_start_ref = git_ref;
        _test_migration = true;
        return this;
    }

    /** Set git repo path for migration test
      **/
    auto ref setMigrationRepo(in Path path) {
        _test_migration_repo = _project.addons(true).getRepo(path);
        _test_migration = true;
        return this;
    }

    /** Use the latest release tag as migration start ref.
      * Fails at run time if no release tags exist for the project's Odoo serie.
      **/
    auto ref setMigrationUseLastRelease() {
        _test_migration_use_last_release = true;
        _test_migration = true;
        return this;
    }

    /** Do not drop database after test completed
      **/
    auto ref setNoDropDatabase() {
        _db_no_drop = true;
        return this;
    }

    /** Enable Coverage
      **/
    auto ref setCoverage(in bool coverage) {
        _coverage = coverage;
        return this;
    }

    /** Add a test tag filter (--test-tags). Requires Odoo 12.0+.
      * May be specified multiple times; all values are joined with commas.
      * Supports Odoo's full tag syntax: plain tags, /module, /module:Class.method,
      * and -tag exclusions.
      **/
    auto ref addTestTag(in string tag) {
        _test_tags ~= tag;
        return this;
    }

    /** Disable automatic installation of modules before tests.
      * This could be usefule to speed up local tests on same database
      **/
    auto ref setNoNeedInstallModules() {
        _need_install_addons_before_test = false;
        return this;
    }

    /** Return CoverageOptions to run server with
      **/
    auto getCoverageOptions() {
        CoverageOptions res = CoverageOptions(_coverage);
        foreach(addon; _addons)
            /*
             * Prefer include over source, because in case of source,
             * coverage mark __init__ files uncovered for some reason.
             * But with 'include' it seems that it works.
             */
            res.include ~= addon.path;
        return res;
    }

    /// Add new module to test run
    auto ref addModule(in OdooAddon addon) {
        if (!addon.manifest.installable) {
            warningf("Addon %s is not installable. Skipping", addon.name);
            return this;
        }

        tracef("Adding %s addon to test runner...", addon.name);
        _addons ~= [addon];
        return this;
    }

    /// ditto
    auto ref addModule(in string addon_name_or_path) {
        auto addon = _project.addons(true).getByString(addon_name_or_path);
        enforce!OdoodException(
            !addon.isNull,
            "Cannot find addon %s!".format(addon_name_or_path));
        return addModule(addon.get);
    }

    /// Add new additional module to install before test
    auto ref addAdditionalModule(in OdooAddon addon) {
        if (!addon.manifest.installable) {
            warningf("Additional addon %s is not installable. Skipping", addon.name);
            return this;
        }

        tracef("Adding additional addon %s to test runner...", addon.name);
        _additional_addons ~= [addon];
        return this;
    }

    /// ditto
    auto ref addAdditionalModule(in string addon_name_or_path) {
        auto addon = _project.addons(true).getByString(addon_name_or_path);
        enforce!OdoodException(
            !addon.isNull,
            "Cannot find addon %s!".format(addon_name_or_path));
        return addAdditionalModule(addon.get);
    }

    /** Enable populate data for specified models
      **/
    auto ref setPopulateModels(in string[] populate_models) {
        enforce!OdoodException(
            _project.odoo.serie >= 14,
            "'populate' feature is available only for Odoo 14.0+");
        _populate_models = populate_models.dup;
        return this;
    }

    /** Set populate size
      **/
    auto ref setPopulateSize(in string size) {
        enforce!OdoodException(
            _project.odoo.serie >= 14,
            "'populate' feature is available only for Odoo 14.0+");
        enforce!OdoodException(
            ["small", "medium", "large"].canFind(size),
            "Populate size could be one of: small, medium, large! Got: %s".format(size));
        _populate_size = size;
        return this;
    }

    /** Register handler that will be called to process each log record
      * captured by this test runner.
      **/
    auto ref registerLogHandler(
            scope void delegate(in OdooLogRecord) handler) {
        _log_handler = handler;
        return this;
    }

    /** Ignore safe warnings
      **/
    auto ref ignoreSafeWarnings(in bool flag=true) {
        _ignore_safe_warnings = flag;
        return this;
    }

    /** Enable collection of test statistics (time + SQL query count) emitted
      * by Odoo's `odoo.tests.stats` logger.
      *
      * Available on Odoo 13.0+ only; on older series the request is ignored
      * with a warning.
      *
      * Params:
      *     detailed = if true, collect per-test-method statistics (DEBUG),
      *         otherwise per-module summary statistics (INFO). Calling with
      *         detailed=true takes precedence over a previous summary request.
      **/
    auto ref setTestStats(in bool detailed=true) {
        if (_project.odoo.serie < OdooSerie(13)) {
            warningf(
                "Test statistics (odoo.tests.stats) are available for " ~
                "Odoo 13.0+ only; ignoring test-stats option for Odoo %s.",
                _project.odoo.serie);
            return this;
        }
        _test_stats_enabled = true;
        if (detailed)
            _test_stats_detailed = true;
        return this;
    }

    /** Get coma-separated list of modules to run tests for.
      *
      * Params:
      *     additional = If set, then include additional addons to the
      *         module list.
      *     existing_only = If set, skip addons whose manifest does not exist
      *         (needed for migration tests to avoid false-positives on newly
      *         added addons). The manifest is checked rather than the directory:
      *         after switching git refs the directory may linger because of
      *         untracked/ignored files (e.g. __pycache__) while the addon is gone.
      *
      * Returns: string, that include coma-separated list of addons
      **/
    string getModuleList(in bool additional=false, in bool existing_only=false) {
        const(OdooAddon)[] res_addons = _addons;
        if (additional)
            res_addons ~= _additional_addons;

        if (existing_only)
            return res_addons.filter!(a => a.manifest_path.exists).map!(a => a.name).join(",");
        return res_addons.map!(a => a.name).join(",");
    }

    /** Handle log record
      **/
    private void handleLogRecord(ref OdooTestResult result, in OdooLogRecord log_record) {
        logToFile(log_record);

        if (!filterLogRecord(log_record))
            return;

        // Capture test statistics from odoo.tests.stats and keep them out of
        // the inline log display; they are rendered as a separate report.
        if (_test_stats_enabled && log_record.logger == "odoo.tests.stats") {
            foreach(stat; parseTestStats(log_record))
                result.addTestStat(stat);
            return;
        }

        if (_log_handler)
            _log_handler(log_record);
        result.addLogRecord(log_record);
    }

    /** Take clean up actions before test finished
      **/
    void cleanUp() {
        if (_temporary_db && _databases.exists(_test_db_name)) {
            if (_db_no_drop == false)
                _databases.drop(_test_db_name);
            else
                infof(
                    "Database %s was not dropt, because test runner " ~
                    "configured to not drop temporary db after test.",
                    _test_db_name);
        }
    }

    /** Check if we need to ignore the record or not
      *
      * Returns: true if record have to be processed and
      *          false if record have to be ignored.
      **/
    private bool filterLogRecord(in OdooLogRecord record) {
        if (this._ignore_safe_warnings && record.log_level == "WARNING") {
            foreach(check; RE_SAFE_WARNINGS)
                if (record.msg.matchFirst(check))
                    return false;
        }
        return true;
    }

    /** Run server command, and handle log output
      *
      * Returns: true if command successful, otherwise false.
      **/
    private bool runServerCommand(ref OdooTestResult result, in string[] options) {
        auto res = _server.pipeServerLog(
            getCoverageOptions(),
            options,
        ).processLogs!true((log_record) {
            handleLogRecord(result, log_record);
        });
        final switch(res) {
            case OdooLogPipe.ServerResult.Interrupted:
                result.setCancelled("Keyboard interrupt");
                return false;
            case OdooLogPipe.ServerResult.Failed:
                result.setFailed();
                return false;
            case OdooLogPipe.ServerResult.Ok:
                // Do nothing. Everything is ok.
                return true;
        }
    }

    /** Run tests (private implementation)
      **/
    private auto runImpl() {
        enforce!OdoodException(
            _addons.length > 0,
            "No addons specified for test");
        enforce!OdoodException(
            !(_test_migration && _test_migration_repo is null),
            "Migration test requested, but migration repo is not specified!");
        enforce!OdoodException(
            !_coverage || _project.venv.path.join("bin", "coverage").exists,
            "Coverage not installed. Please, install it via 'odood venv install-py-packages coverage' to continue.");

        OdooTestResult result;
        result.setMigrationTest(_test_migration);

        auto watch_total = StopWatch(AutoStart.yes);
        scope(exit) result.setDurationTotal(watch_total.peek());

        // Switch branch to migration start ref
        string initial_git_ref;
        if (_test_migration) {
            // Get current branch, and if repo is in detached head mode,
            // then save current commit, to return to after migration.
            initial_git_ref = _test_migration_repo.getCurrBranch.get(
                _test_migration_repo.getCurrCommit);

            if (_test_migration_use_last_release) {
                auto latest = _test_migration_repo.getLatestRelease(
                    _project.odoo.serie);
                enforce!OdoodException(
                    !latest.isNull,
                    ("No release tags found for serie %s. "
                    ~ "Create a release first or use --migration-start-ref.").format(
                        _project.odoo.serie));
                auto tag = latest.get.toString;
                infof(
                    "Switching to last release tag %s before migration tests...",
                    tag);
                _test_migration_repo.fetchTag(tag);
                _test_migration_repo.switchBranchTo(tag);
            } else if (_test_migration_start_ref) {
                infof(
                    "Switching to %s ref before running migration tests...",
                    _test_migration_start_ref);
                _test_migration_repo.fetchOrigin();
                _test_migration_repo.switchBranchTo(_test_migration_start_ref);
            } else {
                infof(
                    "Switching to origin/%s ref before running migration tests...",
                    _project.odoo.serie);
                _test_migration_repo.fetchOrigin(_project.odoo.serie.toString);
                _test_migration_repo.switchBranchTo(
                    "origin/" ~ _project.odoo.serie.toString);
            }

            // process odoo_requirements.txt if needed
            // (to ensure all dependencies present)
            if (_test_migration_repo.path.join("odoo_requirements.txt").exists)
                _project.addons(true).processOdooRequirements(
                    _test_migration_repo.path.join("odoo_requirements.txt"));

            // Link module from migration start ref
            _project.addons(true).link(
                _test_migration_repo.path,
                true,   // Recursive
                true,   // Force
            );
        }
        scope(exit) {
            // Ensure that on exit repo will be returned in it's correct state
            if (_test_migration && _test_migration_repo) {
                string current_git_ref = _test_migration_repo.getCurrBranch.get(
                    _test_migration_repo.getCurrCommit);
                if (_test_migration && current_git_ref != initial_git_ref) {
                    infof("Switching back to %s ...", initial_git_ref);
                    _test_migration_repo.switchBranchTo(initial_git_ref);
                }
            }
            cleanUp();
        }

        // Configure test database (create if needed)
        getOrCreateTestDb();

        // Get free ports for test run to avoid conflicts with other instances
        auto testHttpPort = getFreePort();
        auto testLongpollingPort = getFreePort();
        infof("Using ports: http=%s, longpolling/gevent=%s", testHttpPort, testLongpollingPort);

        // Precompute option for http port
        // (different on different odoo versions)
        auto opt_http_port = _project.odoo.serie > OdooSerie(10) ?
                "--http-port=%s".format(testHttpPort) :
                "--xmlrpc-port=%s".format(testHttpPort);

        if (_need_install_addons_before_test) {
            infof("Installing modules before test...");
            auto cmd_res = runServerCommand(
                result,
                [
                    // Note, that in case of migration tests, we install only addons,
                    // that exists at the moment, thus available for installation.
                    // This is needed to avoid false-positives on adddons that were added in recent version.
                    "--init=%s".format(getModuleList(additional:true, existing_only: _test_migration)),
                    "--log-level=warn",
                    "--stop-after-init",
                    "--workers=0",
                    _project.odoo.serie < OdooSerie(16) ?
                        "--longpolling-port=%s".format(testLongpollingPort) :
                        "--gevent-port=%s".format(testLongpollingPort),
                    opt_http_port,
                    "--database=%s".format(_test_db_name),
                ]
            );
            if (!cmd_res) return result;
        }

        if (_populate_models.length > 0) {
            // Populate database before running tests
            infof(
                "Running 'populate' for database %s for models (%s) with size %s...",
                _test_db_name,
                _populate_models.join(","),
                _populate_size,
            );
            warningf("This feature is deprecated, because in Odoo 18 changed the way of population.");
            auto cmd_res = runServerCommand(
                result,
                [
                    "populate",
                    "--database=%s".format(_test_db_name),
                    "--models=%s".format(_populate_models.join(",")),
                    "--size=%s".format(_populate_size),
                    "--log-level=warn",
                ]
            );
            if (!cmd_res) return result;
        }

        if (_test_migration) {
            infof("Switching back to %s ...", initial_git_ref);
            _test_migration_repo.switchBranchTo(initial_git_ref);

            // TODO: clean -fdx ?

            // process odoo_requirements.txt if needed
            if (_test_migration_repo.path.join("odoo_requirements.txt").exists)
                _project.addons(true).processOdooRequirements(
                    _test_migration_repo.path.join("odoo_requirements.txt"));

            // Link module from current branch
            _project.addons(true).link(
                _test_migration_repo.path,
                true,   // recursive
                true,   // Force
            );
            _project.lodoo.addonsUpdateList(_test_db_name, true);

            infof("Updating modules to run migrations before running tests...");
            auto cmd_res = runServerCommand(
                result,
                [
                    "--update=%s".format(getModuleList(true)),
                    "--log-level=info",
                    "--stop-after-init",
                    "--workers=0",
                    "--database=%s".format(_test_db_name),
                ]
            );
            if (!cmd_res) return result;
        }

        auto watch_tests = StopWatch(AutoStart.yes);
        scope(exit) result.setDurationTests(watch_tests.peek());

        infof("Running tests for modules: %s", getModuleList);
        auto test_args = [
            "--update=%s".format(getModuleList),
            "--log-level=info",
            "--stop-after-init",
            "--workers=0",
            "--test-enable",
            "--database=%s".format(_test_db_name),
        ];
        if (!_test_tags.empty) {
            enforce!OdoodException(
                _project.odoo.serie >= OdooSerie(12),
                "--test-tags requires Odoo 12.0 or later");
            test_args ~= "--test-tags=%s".format(_test_tags.join(","));
        }
        if (_test_stats_enabled)
            // Additive to --log-level above: raises only the odoo.tests.stats
            // logger so per-module (INFO) or per-method (DEBUG) stats are emitted.
            test_args ~= "--log-handler=odoo.tests.stats:%s".format(
                _test_stats_detailed ? "DEBUG" : "INFO");
        auto cmd_res = runServerCommand(result, test_args);
        if (!cmd_res) return result;

        if (!result.errors.empty)
            result.setFailed();
        else
            result.setSuccess();

        return result;
    }

    /** Run the test
      **/
    auto run() {
        try {
            return runImpl();
        } catch (OdoodException e) {
            cleanUp();
            throw e;
        }
    }
}
