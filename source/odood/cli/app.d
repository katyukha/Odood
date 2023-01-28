module odood.cli.app;

private import std.logger;
private import std.format: format;

private import commandr: Program, ProgramArgs, Option, Flag, parse;
import consolecolors: cwritefln, escapeCCL;

private import odood.lib: _version;
private import odood.lib.exception: OdoodException;
private import odood.cli.logger: OdoodLogger;
private import odood.cli.core: OdoodProgram, OdoodCommand;
private import odood.cli.commands.init: CommandInit;
private import odood.cli.commands.server:
    CommandServer, CommandServerStart, CommandServerStop, CommandServerRestart;
private import odood.cli.commands.database: CommandDatabase, CommandDatabaseList;
private import odood.cli.commands.status: CommandStatus;
private import odood.cli.commands.addons:
    CommandAddons, CommandAddonsList, CommandAddonsUpdateList;
private import odood.cli.commands.repository: CommandRepository;
private import odood.cli.commands.config: CommandConfig;
private import odood.cli.commands.test: CommandTest;
private import odood.cli.commands.venv: CommandVenv;
private import odood.cli.commands.discover: CommandDiscover;


/** Class that represents main OdoodProgram
  **/
class App: OdoodProgram {

    this() {
        super("odood", _version);
        this.summary("Easily manage odoo installations.");
        this.add(new CommandInit());
        this.add(new CommandServer());
        this.add(new CommandStatus());
        this.add(new CommandDatabase());
        this.add(new CommandAddons());
        this.add(new CommandConfig());
        this.add(new CommandTest());
        this.add(new CommandRepository());
        this.add(new CommandVenv());
        this.add(new CommandDiscover());

        // shortcuts
        this.add(new CommandServerStart());
        this.add(new CommandServerStop());
        this.add(new CommandServerRestart());
        this.add(new CommandDatabaseList("lsd"));
        this.add(new CommandAddonsList("lsa"));
        this.add(new CommandAddonsUpdateList("ual"));

        // Options
        this.add(new Flag(
            "v", "verbose", "Enable verbose output").repeating());
    }

    /** Setup logging for provided verbosity
      *
      * Verbosity levels:
      *
      * - all (3)
      * - trace (2)
      * - info (1)
      * - warning (default)
      *
      **/
    void setUpLogging(in int verbosity) {
        auto log_level = LogLevel.warning;
        if (verbosity >= 3)
            log_level = LogLevel.all;
        else if (verbosity >= 2)
            log_level = LogLevel.trace;
        else if (verbosity >= 1)
            log_level = LogLevel.info;

        sharedLog = cast(shared) new OdoodLogger(log_level);
    }

    /** So setup actions before running any specific logic
      **/
    override void setup(scope ref ProgramArgs args) {
        uint verbosity = args.occurencesOf("verbose");

        setUpLogging(verbosity);

        return super.setup(args);
    }

    // Overridden to add additional error handling
    override int run(ref string[] args) {
        try {
            return super.run(args);
        } catch (OdoodException e) {
            // TODO: Use custom colodred formatting for errors
            error(escapeCCL("Odood Exception catched: %s".format(e)));
            return 1;
        } catch (Exception e) {
            // TODO: Use custom colodred formatting for errors
            error(escapeCCL("Exception catched: %s".format(e)));
            return 1;
        }
    }
}
