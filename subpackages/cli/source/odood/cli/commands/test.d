module odood.cli.commands.test;

private import std.logger;
private import std.stdio;
private import std.format: format;
private import std.exception: enforce;
private import std.string: join, empty;
private import std.conv: to;
private import std.typecons: Nullable, nullable;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;
private import colored;

private import odood.cli.core: OdoodCommand, exitWithCode;
private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.log: OdooLogProcessor, OdooLogRecord;
private import odood.lib.exception: OdoodException;


/** Color log level, depending on log level itself
  *
  * Params:
  *     rec = OdooLogRecord, that represents single log statement
  * Returns:
  *     string that contains colored log level
  **/
auto colorLogLevel(in ref OdooLogRecord rec) {
    switch (rec.log_level) {
        case "DEBUG":
            return rec.log_level.bold.lightGray;
        case "INFO":
            return rec.log_level.bold.green;
        case "WARNING":
            return rec.log_level.bold.yellow;
        case "ERROR":
            return rec.log_level.bold.red;
        case "CRITICAL":
            return rec.log_level.bold.red;
        default:
            return rec.log_level.bold;
    }
}


/** Print single log record to stdout, applying colors
  **/
void printLogRecord(in ref OdooLogRecord rec) {
    writefln(
        "%s %s %s %s %s: %s",
        rec.date.lightBlue,
        rec.process_id.to!string.lightGray,
        rec.colorLogLevel,
        rec.db.cyan,
        rec.logger.magenta,
        rec.msg);
}


/** Print single log record to stdout in simplified form, applying colors
  **/
void printLogRecordSimplified(in ref OdooLogRecord rec) {
    import std.regex;

    immutable auto RE_LOG_RECORD_START = ctRegex!(
        r"(?P<date>\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\,\d{3})\s" ~
        r"(?P<processid>\d+)\s" ~
        r"(?P<loglevel>\S+)\s" ~
        r"(?P<db>\S+)\s" ~
        r"(?P<logger>\S+):\s(?=\`)");

    auto msg = rec.msg.replaceAll(
        RE_LOG_RECORD_START, "${loglevel} ${logger}: ");

    writefln(
        "%s %s: %s",
        rec.colorLogLevel,
        rec.logger.magenta,
        msg);
}


class CommandTest: OdoodCommand {
    this() {
        super("test", "Run tests for mudles.");
        this.add(new Flag(
            "t", "temp-db", "Create temporary database for tests."));
        this.add(new Flag(
            null, "no-drop-db",
            "Do not drop temporary database after test completed."));
        this.add(new Flag(
            null, "isw", "Ignore warnings that are considered safe."));
        this.add(new Flag(
            null, "migration", "Run migration against stable branch."));
        this.add(new Flag(
            null, "coverage", "Calculate code coverage."));
        this.add(new Flag(
            null, "coverage-report", "Print coverage report."));
        this.add(new Flag(
            null, "coverage-html", "Prepare HTML report for coverage."));
        this.add(new Flag(
            null, "coverage-skip-covered", "Skip covered files in coverage report."));
        this.add(new Option(
            null, "coverage-fail-under", "Fail if coverage is less then specified value."));
        this.add(new Flag(
            null, "no-error-report", "Do not print error report in the end of the test."));
        this.add(new Flag(
            null, "error-report", "Print error report in the end of the test."));
        this.add(new Option(
            "d", "db", "Database to run tests for."));
        this.add(new Option(
            null, "dir", "Directory to search for addons to test").repeating);
        this.add(new Option(
            null, "dir-r",
            "Directory to recursively search for addons to test").repeating);
        this.add(new Option(
            null, "migration-start-ref",
            "git reference (branch/commit/tag) to start migration from"));
        this.add(new Option(
            null, "migration-repo",
            "run migration tests for repo specified by path"));
        this.add(new Argument(
            "addon", "Name of addon to run tests for.").optional.repeating);
    }

    public override void execute(ProgramArgs args) {
        import std.process: wait, Redirect;
        import std.array;
        auto project = Project.loadProject;

        auto testRunner = project.testRunner();

        testRunner.registerLogHandler((in ref rec) {
            printLogRecord(rec);
        });

        if (args.flag("isw"))
            testRunner.ignoreSafeWarnings();

        foreach(string search_path; args.options("dir"))
            foreach(addon; project.addons.scan(Path(search_path), false))
                testRunner.addModule(addon);

        foreach(string search_path; args.options("dir-r"))
            foreach(addon; project.addons.scan(Path(search_path), true))
                testRunner.addModule(addon);

        foreach(addon_name; args.args("addon"))
            testRunner.addModule(addon_name);

        if (args.flag("temp-db"))
            testRunner.useTemporaryDatabase();
        else if (args.option("db") && !args.option("db").empty)
            testRunner.setDatabaseName(args.option("db"));

        // Enable coverage if one of coverage opts passed
        bool coverage = args.flag("coverage");
        if (args.flag("coverage-report")) coverage = true;
        if (args.flag("coverage-html")) coverage = true;

        testRunner.setCoverage(coverage);

        if (args.flag("migration"))
            testRunner.enableMigrationTest();
        if (!args.option("migration-repo").empty)
            testRunner.setMigrationRepo(Path(args.option("migration-repo")));
        if (!args.option("migration-start-ref").empty)
            testRunner.setMigrationStartRef(args.option("migration-start-ref"));

        if (testRunner.test_migration && !testRunner.migration_repo)
            testRunner.setMigrationRepo(Path.current);

        if (args.flag("no-drop-db"))
            testRunner.setNoDropDatabase();

        auto res = testRunner.run();

        if (res.success) {
            writeln();
            writeln("*".replicate(24).green);
            writeln("* ".green, "Test result: ".bold, "SUCCESS".bold.green, " *".green);
            writeln("*".replicate(24).green);
        } else {
            if (args.flag("error-report") || !args.flag("no-error-report")) {
                writeln();
                writeln("*".replicate(19).red);
                writeln("* ".red, "Reported errors".bold, " *".red);
                writeln("*".replicate(19).red);
                foreach(error; res.errors) {
                    printLogRecordSimplified(error);
                }
            }
            writeln();
            writeln("*".replicate(23).red);
            writeln("* ".red, "Test result: ".bold, "FAILED".bold.red, " *".red);
            writeln("*".replicate(23).red);
        }

        // Handle coverage report
        if (coverage)
            project.venv.runE(["coverage", "combine"]);

        if (args.flag("coverage-html")) {
            auto coverage_html_options = [
                "--directory=%s".format(Path.current.join("htmlcov")),
            ];
            if (args.flag("coverage-skip-covered"))
                coverage_html_options ~= "--skip-covered";

            project.venv.runE([
                "coverage", "html",
            ] ~ coverage_html_options);
            writefln(
                "Coverage report saved at %s.\n" ~
                "Just open url (%s) in your browser to view coverage report.",
                Path.current.join("htmlcov").toString.underlined.blue,
                "file://%s/index.html".format(
                    Path.current.join("htmlcov").toString).underlined.blue);
        }

        if (args.flag("coverage-report")) {
            string[] coverage_report_options = [];
            if (args.flag("coverage-skip-covered"))
                coverage_report_options ~= "--skip-covered";
            if (!args.option("coverage-fail-under").empty)
                coverage_report_options ~= [
                    "--fail-under",
                    args.option("coverage-fail-under"),
                ];

            auto coverage_report_res = project.venv.run(
                ["coverage", "report",] ~ coverage_report_options
            );

            writeln();
            if (coverage_report_res.status == 0) {
                writeln("*".replicate(23).blue);
                writeln("* ".blue, "Coverage Report: ".bold, "OK".bold.green, " *".blue);
                writeln("*".replicate(23).blue);
                writeln(coverage_report_res.output);
            } else {
                writeln("*".replicate(27).blue);
                writeln("* ".blue, "Coverage Report: ".bold, "FAILED".bold.red, " *".blue);
                writeln("*".replicate(27).blue);
                writeln(coverage_report_res.output);

                // Exit with error code
                // TODO: Try to avoid exception;
                exitWithCode(1, "Test failed");
            }
        }

        if (!res.success)
            // TODO: Try to avoid exception, and just return non-zero exit-code
            exitWithCode(1, "Test failed");
    }
}



