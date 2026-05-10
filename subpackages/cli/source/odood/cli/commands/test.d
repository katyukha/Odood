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
private import odood.utils.addons.addon: OdooAddon;
private import odood.utils.odoo.serie: OdooSerie;


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
    string[] populateModel;
    Nullable!string populateSize;

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
        this.addOption!(populateModel)("", "populate-model",
            "Name of model to populate. Could be specified multiple times.");
        this.addOption!(populateSize)("", "populate-size", "Population size.")
            .acceptsValues(["small", "medium", "large"]);
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

        if (testRunner.test_migration && !testRunner.migration_repo)
            testRunner.setMigrationRepo(Path.current);

        if (noDropDb)
            testRunner.setNoDropDatabase();

        if (!populateModel.empty)
            testRunner.setPopulateModels(populateModel);
        if (!populateSize.isNull)
            testRunner.setPopulateSize(populateSize.get);

        auto res = testRunner.run();

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
