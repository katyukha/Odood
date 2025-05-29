module odood.cli.commands.test;

private import core.time;

private import std.logger;
private import std.stdio: writeln, writefln;
private import std.format: format;
private import std.exception: enforce;
private import std.string: join, empty, rightJustify;
private import std.conv: to;
private import std.typecons: Nullable, nullable;
private import std.algorithm;
private import std.regex;
private import std.array;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs, acceptsValues;
private import colored;

private import odood.cli.core: OdoodCommand, OdoodCLIException, exitWithCode;
private import odood.cli.utils: printLogRecord, printLogRecordSimplified;
private import odood.lib.project: Project;
private import odood.lib.odoo.log: OdooLogProcessor, OdooLogRecord;
private import odood.utils.addons.addon: OdooAddon;
private import odood.utils.odoo.serie: OdooSerie;


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
            null, "simplified-log", "Display simplified log messages."));
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
        this.add(new Flag(
            null, "coverage-ignore-errors", "Ignore coverage errors."));
        this.add(new Option(
            null, "coverage-fail-under", "Fail if coverage is less then specified value."));
        this.add(new Flag(
            null, "no-error-report", "Do not print error report in the end of the test."));
        this.add(new Flag(
            null, "error-report", "Print error report in the end of the test."));
        this.add(new Flag(
            null, "warning-report", "Print warning report in the end of the test."));
        this.add(new Option(
            "d", "db", "Database to run tests for."));
        this.add(new Option(
            null, "additional-addon",
            "Specify additional addon to install before test. ").repeating);

        this.add(new Flag(
            null, "no-install-addons", "Do not install addons before test. Could be useful to speed up local tests."));

        // Search for addons options and arguments
        this.add(new Option(
            null, "dir", "Directory to search for addons to test").repeating);
        this.add(new Option(
            null, "dir-r",
            "Directory to recursively search for addons to test").repeating);
        this.add(
            new Option(
                "f", "file",
                "Read addons names from file (addon names must be separated by new lines)"
            ).optional().repeating());
        this.add(new Option(
            null, "skip",
            "Skip (do not run tests) addon specified by name.").repeating);
        this.add(new Option(
            null, "skip-re",
            "Skip (do not run tests) addon specified by regex.").repeating);
        this.add(
            new Option(
                null, "skip-file",
                "Skip addons listed in specified file (addon names must be separated by new lines)"
            ).optional().repeating());
        this.add(new Argument(
            "addon", "Name of addon to run tests for.").optional.repeating);

        // Migration options
        this.add(new Option(
            null, "migration-start-ref",
            "git reference (branch/commit/tag) to start migration from"));
        this.add(new Option(
            null, "migration-repo",
            "run migration tests for repo specified by path"));

        // Populate database with test data before running tests
        this.add(new Option(
            null, "populate-model", "Name of model to populate. Could be specified multiple times.").repeating);
        this.add(new Option(
            null, "populate-size", "Population size."
            ).acceptsValues(["small", "medium", "large"]));
    }

    /** Find addons to test
      **/
    private auto findAddons(ProgramArgs args, in Project project) {
        string[] skip_addons = args.options("skip");
        auto skip_regexes = args.options("skip-re").map!(r => regex(r)).array;

        foreach(path; args.options("skip-file"))
            foreach(addon; project.addons.parseAddonsList(Path(path)))
                skip_addons ~= addon.name;

        OdooAddon[] addons;
        foreach(search_path; args.options("dir"))
            foreach(addon; project.addons.scan(Path(search_path), false)) {
                if (skip_addons.canFind(addon.name)) continue;
                if (skip_regexes.canFind!((re, addon) => !addon.matchFirst(re).empty)(addon.name)) continue;
                addons ~= addon;
            }

        foreach(search_path; args.options("dir-r"))
            foreach(addon; project.addons.scan(Path(search_path), true)) {
                if (skip_addons.canFind(addon.name)) continue;
                if (skip_regexes.canFind!((re, addon) => !addon.matchFirst(re).empty)(addon.name)) continue;
                addons ~= addon;
            }

        foreach(addon_name; args.args("addon")) {
            if (skip_addons.canFind(addon_name)) continue;
            if (skip_regexes.canFind!((re, addon) => !addon.matchFirst(re).empty)(addon_name)) continue;

            auto addon = project.addons(true).getByString(addon_name);
            enforce!OdoodCLIException(
                !addon.isNull,
                "Cannot find addon %s!".format(addon_name));
            addons ~= addon.get;
        }

        foreach(path; args.options("file")) {
            foreach(addon; project.addons.parseAddonsList(Path(path))) {
                if (skip_addons.canFind(addon.name)) continue;
                if (skip_regexes.canFind!((re, addon) => !addon.matchFirst(re).empty)(addon.name)) continue;
                addons ~= addon;
            }
        }
        return addons;
    }

    public override void execute(ProgramArgs args) {
        import std.process: wait, Redirect;
        import std.array;
        auto project = Project.loadProject;

        auto testRunner = project.testRunner();

        if (args.flag("simplified-log"))
            testRunner.registerLogHandler((in rec) {
                printLogRecordSimplified(rec);
            });
        else
            testRunner.registerLogHandler((in rec) {
                printLogRecord(rec);
            });

        if (args.flag("isw"))
            testRunner.ignoreSafeWarnings();

        if (args.flag("no-install-addons"))
            testRunner.setNoNeedInstallModules();

        foreach(addon; findAddons(args, project)) {
            testRunner.addModule(addon);
        }

        foreach(addon_name; args.options("additional-addon"))
            testRunner.addAdditionalModule(addon_name);

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

        if (!args.options("populate-models").empty)
            testRunner.setPopulateModels(args.options("populate-models"));
        if (!args.option("populate-size").empty)
            testRunner.setPopulateModels(args.options("populate-size"));

        auto res = testRunner.run();

        // TODO: Try to use tabletool to generate table-like output
        if (args.flag("warning-report") && !res.warnings.empty) {
            writeln();
            writeln("*".replicate(21).yellow);
            writeln("* ".yellow, "Reported warnings".bold, " *".yellow);
            writeln("*".replicate(21).yellow);
            foreach(warning; res.warnings.array.dup.sort!((a, b) => a.msg < b.msg).uniq!((a, b) => a.msg == b.msg))
                printLogRecordSimplified(warning);
        }

        if (res.success) {
            writeln();
            writeln("*".replicate(45).green);
            writeln("* ".green, "Test result:    ".bold, "SUCCESS".rightJustify(25).bold.green, " *".green);
            writeln("* ".green, "-".replicate(41).lightGray, " *".green);
            writeln("* ".green, "Tests duration: ", res.testsDuration.total!"seconds".seconds.to!string.rightJustify(25).blue, " *".green);
            writeln("* ".green, "Total duration: ", res.totalDuration.total!"seconds".seconds.to!string.rightJustify(25).blue, " *".green);
            writeln("*".replicate(45).green);
        } else {
            if (args.flag("error-report") || !args.flag("no-error-report")) {
                writeln();
                writeln("*".replicate(19).red);
                writeln("* ".red, "Reported errors".bold, " *".red);
                writeln("*".replicate(19).red);
                foreach(error; res.errors)
                    printLogRecordSimplified(error);
            }
            writeln();
            writeln("*".replicate(45).red);
            writeln("* ".red, "Test result:    ".bold, "FAILED".rightJustify(25).bold.red, " *".red);
            writeln("* ".red, "-".replicate(41).lightGray, " *".red);
            writeln("* ".red, "Tests duration: ", res.testsDuration.total!"seconds".seconds.to!string.rightJustify(25).blue, " *".red);
            writeln("* ".red, "Total duration: ", res.totalDuration.total!"seconds".seconds.to!string.rightJustify(25).blue, " *".red);
            writeln("*".replicate(45).red);
        }

        // Handle coverage report
        if (coverage)
            project.venv.runE(["coverage", "combine"]);

        if (args.flag("coverage-html")) {
            auto coverage_html_options = [
                "--directory=%s".format(Path.current.join("htmlcov")),
            ];
            if (args.flag("coverage-skip-covered") || testRunner.test_migration)
                coverage_html_options ~= "--skip-covered";
            if (args.flag("coverage-ignore-errors"))
                coverage_html_options ~= ["--ignore-errors"];

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
            if (args.flag("coverage-ignore-errors"))
                coverage_report_options ~= ["--ignore-errors"];

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
                exitWithCode(1, "Test failed");
            }
        }

        if (!res.success)
            exitWithCode(1, "Test failed");
    }
}



