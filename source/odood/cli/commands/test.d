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
private import consolecolors: cwritefln, escapeCCL;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project, ProjectConfig;
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
        this.add(new Option(
            "d", "db", "Database to run tests for."));
        this.add(new Flag(
            "t", "temp-db", "Create temporary database for tests."));
        this.add(new Argument(
            "addon", "Name of addon to run tests for.").required.repeating);
    }

    public override void execute(ProgramArgs args) {
        import std.process: wait, Redirect;
        auto project = new Project();

        auto testRunner = project.testRunner();

        testRunner.registerLogHandler((in ref rec) {
            printLogRecord(rec);
        });

        foreach(addon_name; args.args("addon"))
            testRunner.addModule(addon_name);

        if (args.flag("temp-db"))
            testRunner.useTemporaryDatabase();
        else if (args.option("db") && !args.option("db").empty)
            testRunner.setDatabaseName(args.option("db"));

        auto res = testRunner.run();
        if (res.success) {
            cwritefln("Test result: <lgreen>SUCCESS</lgreen>");
        } else {
            cwritefln("Test result: <red>FAILED</red>\nErrors listed below:");
            foreach(error; res.errors) {
                printLogRecord(error);
            }
        }
    }
}


