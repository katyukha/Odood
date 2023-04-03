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

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.log: OdooLogProcessor, OdooLogRecord;
private import odood.lib.exception: OdoodException;


void printLogRecord(in ref OdooLogRecord rec) {
    auto colored_log_level = () {
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
    }();
    writefln(
        "%s %s %s %s %s: %s",
        rec.date.lightBlue,
        rec.process_id.to!string.lightGray,
        colored_log_level,
        rec.db.cyan,
        rec.logger.magenta,
        rec.msg);
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
            null, "error-report", "Print all errors found in the end of output"));
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
            writeln("-".replicate(80).green);
            writeln("Test result: ", "SUCCESS".bold.green);
            writeln("-".replicate(80).green);
        } else {
            writeln("-".replicate(80).red);
            writefln("Test result: ", "FAILED".bold.red);
            writeln("-".replicate(80).red);
            if (args.flag("error-report")) {
                writeln("Errors listed below:");
                writeln("-".replicate(80).lightGray);
                foreach(error; res.errors) {
                    printLogRecord(error);
                    writeln("-".replicate(80).lightGray);
                }
            }
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
                "Coverage report saved at <blue>%s</blue>.\n" ~
                "Just open url (<blue>file://%s/index.html</blue>) in " ~
                "your browser to view coverage report.",
                Path.current.join("htmlcov").toString.underlined.blue,
                Path.current.join("htmlcov").toString.underlined.blue);
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

            writeln(
                project.venv.runE(
                    ["coverage", "report",] ~ coverage_report_options
                ).output
            );
        }
    }
}



