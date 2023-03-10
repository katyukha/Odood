module odood.cli.app;

private import std.logger;
private import std.format: format;

private import commandr: Program, ProgramArgs, Option, Flag, parse;
import consolecolors: cwritefln, escapeCCL;

private import odood.lib: _version;
private import odood.lib.exception: OdoodException;
private import odood.cli.core.logger: OdoodLogger;
private import odood.cli.core: OdoodProgram, OdoodCommand;
private import odood.cli.commands.init: CommandInit;
private import odood.cli.commands.server:
    CommandServer, CommandServerStart, CommandServerStop, CommandServerRestart,
    CommandServerBrowse;
private import odood.cli.commands.database: CommandDatabase, CommandDatabaseList;
private import odood.cli.commands.status: CommandStatus;
private import odood.cli.commands.addons:
    CommandAddons, CommandAddonsList, CommandAddonsUpdateList;
private import odood.cli.commands.repository: CommandRepository;
private import odood.cli.commands.config: CommandConfig;
private import odood.cli.commands.test: CommandTest;
private import odood.cli.commands.venv: CommandVenv;
private import odood.cli.commands.discover: CommandDiscover;
private import odood.cli.commands.log: CommandLogView;
private import odood.cli.commands.script: CommandScript;


/** Class that represents main OdoodProgram
  **/
class App: OdoodProgram {

    private bool enable_debug = false;

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
        this.add(new CommandLogView());
        this.add(new CommandScript());

        // shortcuts
        this.add(new CommandServerStart());
        this.add(new CommandServerStop());
        this.add(new CommandServerRestart());
        this.add(new CommandServerBrowse());
        this.add(new CommandDatabaseList("lsd"));
        this.add(new CommandAddonsList("lsa"));
        this.add(new CommandAddonsUpdateList("ual"));

        // Options
        this.add(new Flag(
            "v", "verbose", "Enable verbose output").repeating());
        this.add(new Flag(
            "q", "quiet", "Hide unnecessary output").repeating());
        this.add(new Flag(
            "d", "debug", "Show additional debug information."));
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
    void setUpLogging(in int verbosity, in int quietness) {
        auto log_verbosity = verbosity - quietness;

        auto log_level = LogLevel.info;  // Default log level
        if (log_verbosity >= 2)
            log_level = LogLevel.all;
        else if (log_verbosity >= 1)
            log_level = LogLevel.trace;
        else if (log_verbosity >= 0)     // Default log level
            log_level = LogLevel.info;
        else if (log_verbosity >= 1)
            log_level = LogLevel.warning;
        else if (log_verbosity >= 2)
            log_level = LogLevel.error;

        std.logger.sharedLog = cast(shared) new OdoodLogger(log_level);
    }

    /** So setup actions before running any specific logic
      **/
    override void setup(scope ref ProgramArgs args) {
        int verbosity = args.occurencesOf("verbose");
        int quietness = args.occurencesOf("quiet");

        if (args.flag("debug"))
            enable_debug = true;

        setUpLogging(verbosity, quietness);

        return super.setup(args);
    }

    // Overridden to add additional error handling
    override int run(ref string[] args) {
        try {
            return super.run(args);
        } catch (OdoodException e) {
            // TODO: Use custom colodred formatting for errors
            if (enable_debug)
                error(escapeCCL("Odood Exception catched:\n%s".format(e)));
            else
                error(escapeCCL("%s".format(e.msg)));
            return 1;
        } catch (Exception e) {
            // TODO: Use custom colodred formatting for errors
            if (enable_debug)
                error(escapeCCL("Exception catched:\n%s".format(e)));
            else
                error(escapeCCL("%s".format(e.msg)));
            return 1;
        }
    }
}
