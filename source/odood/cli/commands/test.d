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
private import consolecolors: cwriteln, cwritefln, escapeCCL;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.log: OdooLogProcessor, OdooLogRecord;
private import odood.lib.exception: OdoodException;


void printLogRecord(in ref OdooLogRecord rec) {
    string format_tmpl = () {
        switch (rec.log_level) {
            case "INFO":
                return "%s %s <green>%s</green> %s %s: %s";
            case "WARNING":
                return "%s %s <yellow>%s</yellow> %s %s: %s";
            case "ERROR":
                return "%s %s <red>%s</red> %s %s: %s";
            case "CRITICAL":
                return "%s %s <red>%s</red> %s %s: %s";
            default:
                return "%s %s %s %s %s: %s";
        }
    }();
    cwritefln(
        format_tmpl,
        rec.date.escapeCCL, rec.process_id, rec.log_level.escapeCCL, rec.db.escapeCCL, rec.logger.escapeCCL, rec.msg.escapeCCL);
}


class CommandTest: OdoodCommand {
    this() {
        super("test", "Run tests for mudles.");
        this.add(new Flag(
            "t", "temp-db", "Create temporary database for tests."));
        this.add(new Flag(
            null, "coverage", "Calculate code coverage."));
        this.add(new Flag(
            null, "coverage-report", "Print coverage report."));
        this.add(new Flag(
            null, "coverage-html", "Prepare HTML report for coverage."));
        this.add(new Option(
            "d", "db", "Database to run tests for."));
        this.add(new Option(
            null, "dir", "Directory to search for addons to test").repeating);
        this.add(new Option(
            null, "dir-r",
            "Directory to recursively search for addons to test").repeating);
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

        bool coverage = args.flag("coverage");
        bool coverage_report = false;
        bool coverage_html = false;

        if (args.flag("coverage-report")) {
            coverage = true;
            coverage_report = true;
        }

        if (args.flag("coverage-html")) {
            coverage = true;
            coverage_html = true;
        }

        testRunner.setCoverage(coverage);

        auto res = testRunner.run();

        if (coverage)
            project.venv.runE(["coverage", "combine"]);

        if (res.success) {
            cwriteln("<green>" ~ "-".replicate(80) ~ "</green>");
            cwritefln("Test result: <lgreen>SUCCESS</lgreen>");
            cwriteln("<green>" ~ "-".replicate(80) ~ "</green>");
        } else {
            cwriteln("<red>" ~ "-".replicate(80) ~ "</red>");
            cwritefln("Test result: <red>FAILED</red>");
            cwriteln("<red>" ~ "-".replicate(80) ~ "</red>");
            cwritefln("Errors listed below:");
            cwriteln("<grey>" ~ "-".replicate(80) ~ "</grey>");
            foreach(error; res.errors) {
                printLogRecord(error);
                cwriteln("<grey>" ~ "-".replicate(80) ~ "</grey>");
            }
        }

        if (coverage_html)
            project.venv.runE([
                "coverage", "html",
                "--directory=%s".format(Path.current.join("htmlcov"))]);
        if (coverage_report)
            write(project.venv.runE(["coverage", "report"]).output);
    }
}



