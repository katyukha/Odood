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
private static import std.process;

private import thepath: Path;
private import darkcommand;
private import colored;

private import odood.cli.core: OdoodCommand, OdoodCLIException, exitWithCode;
private import odood.cli.utils: printLogRecord, printLogRecordSimplified;
private import odood.lib.project: Project;
private import odood.lib.odoo.log: OdooLogProcessor, OdooLogRecord;
private import odood.lib.odoo.test: OdooTestStat;
private import odood.utils.addons.addon: OdooAddon;
private import odood.utils.odoo.serie: OdooSerie;


/// Default number of rows shown in each per-method test-profiling table.
private enum size_t DEFAULT_TEST_STATS_LIMIT = 20;


class CommandTest: OdoodCommand {
    bool tempDb;
    bool noDropDb;
    bool isw;
    bool simplifiedLog;
    bool migration;
    bool coverage;
    bool coverageReport;
    bool coverageHtml;
    bool coverageSkipCovered;
    bool coverageIgnoreErrors;
    Nullable!string coverageFailUnder;
    bool noErrorReport;
    bool errorReport;
    bool warningReport;
    Nullable!string db;
    string[] additionalAddon;
    bool noInstallAddons;
    Path[] dir;
    Path[] dirR;
    Path[] file;
    string[] skip;
    string[] skipRe;
    Path[] skipFile;
    string[] addon;
    Nullable!string migrationStartRef;
    Nullable!Path migrationRepo;
    bool migrationLastRelease;
    string[] populateModel;
    Nullable!string populateSize;
    string[] scriptAfterInstall;
    string[] scriptAfterMigration;
    string[] testTag;
    bool testStatsSummary;
    bool testStatsDetailed;
    bool testStatsAll;

    this() {
        super("test", "Run tests for modules.");
        this.addFlag!(tempDb)("t", "temp-db", "Create temporary database for tests.");
        this.addFlag!(noDropDb)("", "no-drop-db",
            "Do not drop temporary database after test completed.");
        this.addFlag!(isw)("", "isw", "Ignore warnings that are considered safe.");
        this.addFlag!(simplifiedLog)("", "simplified-log", "Display simplified log messages.");
        this.addFlag!(migration)("", "migration", "Run migration against stable branch.");
        this.addFlag!(coverage)("", "coverage", "Calculate code coverage.");
        this.addFlag!(coverageReport)("", "coverage-report", "Print coverage report.");
        this.addFlag!(coverageHtml)("", "coverage-html", "Prepare HTML report for coverage.");
        this.addFlag!(coverageSkipCovered)("", "coverage-skip-covered",
            "Skip covered files in coverage report.");
        this.addFlag!(coverageIgnoreErrors)("", "coverage-ignore-errors",
            "Ignore coverage errors.");
        this.addOption!(coverageFailUnder)("", "coverage-fail-under",
            "Fail if coverage is less than specified value.");
        this.addFlag!(noErrorReport)("", "no-error-report",
            "Do not print error report in the end of the test.");
        this.addFlag!(errorReport)("", "error-report",
            "Print error report in the end of the test.");
        this.addFlag!(warningReport)("", "warning-report",
            "Print warning report in the end of the test.");
        this.addOption!(db)("d", "db", "Database to run tests for.");
        this.addOption!(additionalAddon)("", "additional-addon",
            "Specify additional addon to install before test.");
        this.addFlag!(noInstallAddons)("", "no-install-addons",
            "Do not install addons before test. Could be useful to speed up local tests.");
        this.addOption!(dir)("", "dir", "Directory to search for addons to test")
            .acceptsDirectories();
        this.addOption!(dirR)("", "dir-r",
            "Directory to recursively search for addons to test")
            .acceptsDirectories();
        this.addOption!(file)("f", "file",
            "Read addons names from file (addon names must be separated by new lines)")
            .acceptsFiles();
        this.addOption!(skip)("", "skip",
            "Skip (do not run tests) addon specified by name.");
        this.addOption!(skipRe)("", "skip-re",
            "Skip (do not run tests) addon specified by regex.");
        this.addOption!(skipFile)("", "skip-file",
            "Skip addons listed in specified file (addon names must be separated by new lines)")
            .acceptsFiles();
        this.addOption!(migrationStartRef)("", "migration-start-ref",
            "git reference (branch/commit/tag) to start migration from");
        this.addOption!(migrationRepo)("", "migration-repo",
            "run migration tests for repo specified by path");
        this.addFlag!(migrationLastRelease)("", "migration-last-release",
            "Start migration test from the latest release tag. "
            ~ "Fails if no release tags exist for the current Odoo serie.");
        this.addOption!(populateModel)("", "populate-model",
            "Name of model to populate. Could be specified multiple times.");
        this.addOption!(populateSize)("", "populate-size", "Population size.")
            .acceptsValues(["small", "medium", "large"]);
        this.addOption!(scriptAfterInstall)("", "script-after-install",
            "Run a script (.py or .sql) after addons are installed, before " ~
            "tests. In migration mode runs on the start ref (old version). " ~
            "Repeatable. Accepts an absolute path, or a name resolved against " ~
            "<repo>/.odood-scripts/, <project>/scripts/, or the current directory.");
        this.addOption!(scriptAfterMigration)("", "script-after-migration",
            "Run a script (.py or .sql) after addons are updated to the " ~
            "current branch (migrations applied), before tests. Migration " ~
            "mode only. Repeatable. Same resolution as --script-after-install.");
        this.addOption!(testTag)("", "test-tag",
            "Filter tests by tag (Odoo 12.0+). Repeatable. Supports Odoo tag syntax: " ~
            "plain tags, /module, /module:Class.method, -tag to exclude.");
        this.addFlag!(testStatsSummary)("", "test-stats-summary",
            "Report per-module test statistics (time + SQL query count). " ~
            "May be combined with --test-stats-detailed. Requires Odoo 13.0+.");
        this.addFlag!(testStatsDetailed)("", "test-stats-detailed",
            "Report per-test-method statistics (time + SQL query count), " ~
            "useful to spot slow tests and N+1 query regressions. May be " ~
            "combined with --test-stats-summary. Requires Odoo 13.0+.");
        this.addFlag!(testStatsAll)("", "test-stats-all",
            "Report both per-module and per-test-method statistics " ~
            "(shortcut for --test-stats-summary --test-stats-detailed). " ~
            "Requires Odoo 13.0+.");
        this.addArgument!(addon)("addon", "Names of addons to run tests for.")
            .defaultValue([]);
    }

    private auto findAddons(in Project project) {
        string[] skip_addons = skip;
        auto skip_regexes = skipRe.map!(r => regex(r)).array;

        foreach(path; skipFile)
            foreach(a; project.addons.parseAddonsList(path))
                skip_addons ~= a.name;

        OdooAddon[] addons;
        foreach(search_path; dir)
            foreach(a; project.addons.scan(search_path, false)) {
                if (skip_addons.canFind(a.name)) continue;
                if (skip_regexes.canFind!((re, name) => !name.matchFirst(re).empty)(a.name)) continue;
                addons ~= a;
            }

        foreach(search_path; dirR)
            foreach(a; project.addons.scan(search_path, true)) {
                if (skip_addons.canFind(a.name)) continue;
                if (skip_regexes.canFind!((re, name) => !name.matchFirst(re).empty)(a.name)) continue;
                addons ~= a;
            }

        foreach(addon_name; addon) {
            if (skip_addons.canFind(addon_name)) continue;
            if (skip_regexes.canFind!((re, name) => !name.matchFirst(re).empty)(addon_name)) continue;

            auto a = project.addons(true).getByString(addon_name);
            enforce!OdoodCLIException(
                !a.isNull,
                "Cannot find addon %s!".format(addon_name));
            addons ~= a.get;
        }

        foreach(path; file) {
            foreach(a; project.addons.parseAddonsList(path)) {
                if (skip_addons.canFind(a.name)) continue;
                if (skip_regexes.canFind!((re, name) => !name.matchFirst(re).empty)(a.name)) continue;
                addons ~= a;
            }
        }
        return addons;
    }

    /** Print the test-profiling report captured during the test run.
      *
      * Odoo's detailed report contains entries at the module, module.Class and
      * module.Class.method aggregation levels.  The two sections of the report
      * are selected independently:
      *   - summary: per-module table (entries with no dot in their name)
      *   - detailed: per-method bottleneck tables (leaf entries — names that
      *     are not a dotted prefix of any other entry)
      * so both can be shown from a single (detailed) run.
      *
      * Params:
      *     stats = statistics captured from the test run
      *     show_summary = render the per-module summary table
      *     show_detailed = render the per-method bottleneck tables
      **/
    private void printTestStatsReport(
            in OdooTestStat[] stats,
            in bool show_summary,
            in bool show_detailed) {
        import tabletool;
        import std.range: take;

        static string fmtTime(in OdooTestStat s) {
            return "%.2fs".format(s.duration.total!"msecs" / 1000.0);
        }
        auto cfg = tabletool.Config(
            tabletool.Style.grid, tabletool.Align.left, true);

        // Module aggregation level: entries without a dot in their name.
        auto modules = stats.filter!(s => !s.name.canFind('.')).array;

        // Leaf entries (individual test methods): names that are not a dotted
        // prefix of any other entry.
        bool[string] aggregates;
        foreach(s; stats) {
            auto parts = s.name.split('.');
            string prefix;
            foreach(i, p; parts[0 .. $ - 1]) {
                prefix = i == 0 ? p : prefix ~ "." ~ p;
                aggregates[prefix] = true;
            }
        }
        auto methods = stats.filter!(s => s.name !in aggregates).array;

        if (modules.empty && methods.empty)
            return;

        writeln();
        writeln("*".replicate(28).blue);
        writeln("* ".blue, "Test profiling report".bold, " *".blue);
        writeln("*".replicate(28).blue);

        if (show_summary && !modules.empty) {
            auto rows = modules.dup.sort!((a, b) => a.duration > b.duration);
            string[][] table = [["Module", "Time", "Queries"]];
            foreach(s; rows)
                table ~= [s.name, fmtTime(s), s.queries.to!string];
            writeln("Per-module summary:".bold);
            writeln(tabulate(table, cfg));
        }

        if (show_detailed && !methods.empty) {
            auto by_time = methods.dup.sort!((a, b) => a.duration > b.duration);
            string[][] slowest = [["Test", "Time", "Queries"]];
            foreach(s; by_time.take(DEFAULT_TEST_STATS_LIMIT))
                slowest ~= [s.name, fmtTime(s), s.queries.to!string];
            writeln("Slowest tests:".bold);
            writeln(tabulate(slowest, cfg));

            auto by_queries = methods.dup.sort!((a, b) => a.queries > b.queries);
            string[][] most_queries = [["Test", "Queries", "Time"]];
            foreach(s; by_queries.take(DEFAULT_TEST_STATS_LIMIT))
                most_queries ~= [s.name, s.queries.to!string, fmtTime(s)];
            writeln("Most queries (possible N+1):".bold);
            writeln(tabulate(most_queries, cfg));
        }

        // The sum over module-level entries represents the whole run.
        auto totals = modules.empty ? methods : modules;
        writefln(
            "Total: %s entries, %s queries.",
            totals.length, totals.map!(s => s.queries).sum);
    }

    override int execute() {
        import std.process: wait, Redirect;
        import std.array;
        auto project = Project.loadProject;

        auto testRunner = project.testRunner();

        if (simplifiedLog)
            testRunner.registerLogHandler((in rec) {
                printLogRecordSimplified(rec);
            });
        else
            testRunner.registerLogHandler((in rec) {
                printLogRecord(rec);
            });

        if (isw)
            testRunner.ignoreSafeWarnings();

        if (noInstallAddons)
            testRunner.setNoNeedInstallModules();

        foreach(a; findAddons(project))
            testRunner.addModule(a);

        foreach(addon_name; additionalAddon)
            testRunner.addAdditionalModule(addon_name);

        if (tempDb)
            testRunner.useTemporaryDatabase();
        else if (!db.isNull && !db.get.empty)
            testRunner.setDatabaseName(db.get);

        bool do_coverage = coverage;
        if (coverageReport) do_coverage = true;
        if (coverageHtml) do_coverage = true;

        testRunner.setCoverage(do_coverage);

        if (migration)
            testRunner.enableMigrationTest();
        if (!migrationRepo.isNull)
            testRunner.setMigrationRepo(migrationRepo.get);
        if (!migrationStartRef.isNull)
            testRunner.setMigrationStartRef(migrationStartRef.get);
        if (migrationLastRelease)
            testRunner.setMigrationUseLastRelease();

        if (testRunner.test_migration && !testRunner.migration_repo)
            testRunner.setMigrationRepo(Path.current);

        if (noDropDb)
            testRunner.setNoDropDatabase();

        if (!populateModel.empty)
            testRunner.setPopulateModels(populateModel);
        if (!populateSize.isNull)
            testRunner.setPopulateSize(populateSize.get);

        foreach(script; scriptAfterInstall)
            testRunner.addScriptAfterInstall(script);
        foreach(script; scriptAfterMigration)
            testRunner.addScriptAfterMigration(script);

        foreach(tag; testTag)
            testRunner.addTestTag(tag);

        immutable show_summary = testStatsSummary || testStatsAll;
        immutable show_detailed = testStatsDetailed || testStatsAll;
        if (show_detailed)
            testRunner.setTestStats(true);
        else if (show_summary)
            testRunner.setTestStats(false);

        auto res = testRunner.run();

        if ((show_summary || show_detailed) && !res.testStats.empty)
            printTestStatsReport(res.testStats, show_summary, show_detailed);

        if (warningReport && !res.warnings.empty) {
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
            if (errorReport || !noErrorReport) {
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

        if (do_coverage)
            project.venv.runner
                .withArgs("coverage", "combine")
                .withFlag(std.process.Config.stderrPassThrough)
                .inWorkDir(Path.current)
                .execute
                .ensureOk!OdoodCLIException(true);

        if (coverageHtml) {
            auto cmd = project.venv.runner
                .withArgs(
                    "coverage",
                    "html",
                    "--directory=%s".format(Path.current.join("htmlcov")));
            if (coverageSkipCovered || testRunner.test_migration)
                cmd.addArgs("--skip-covered");
            if (coverageIgnoreErrors)
                cmd.addArgs("--ignore-errors");

            cmd.inWorkDir(Path.current)
                .withFlag(std.process.Config.stderrPassThrough)
                .execute
                .ensureOk!OdoodCLIException(true);

            writefln(
                "Coverage report saved at %s.\n" ~
                "Just open url (%s) in your browser to view coverage report.",
                Path.current.join("htmlcov").toString.underlined.blue,
                "file://%s/index.html".format(
                    Path.current.join("htmlcov").toString).underlined.blue);
        }

        if (coverageReport) {
            auto cmd = project.venv.runner
                .withArgs("coverage", "report")
                .withFlag(std.process.Config.stderrPassThrough);
            if (coverageSkipCovered || testRunner.test_migration)
                cmd.addArgs("--skip-covered");
            if (coverageIgnoreErrors)
                cmd.addArgs("--ignore-errors");
            if (!coverageFailUnder.isNull)
                cmd.addArgs("--fail-under", coverageFailUnder.get);

            auto coverage_report_res = cmd.inWorkDir(Path.current).execute;

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

                exitWithCode(1, "Test failed");
            }
        }

        if (!res.success)
            exitWithCode(1, "Test failed");
        return 0;
    }
}
