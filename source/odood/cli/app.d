module odood.cli.app;

private import std.logger;

private import commandr: Program, ProgramArgs, Option, Flag, parse;
import consolecolors: cwritefln, escapeCCL;

private import odood.lib: _version;
private import odood.lib.exception: OdoodException;
private import odood.cli.core: OdoodProgram, OdoodCommand;
private import odood.cli.commands.init: CommandInit;
private import odood.cli.commands.server:
    CommandServer, CommandServerStart, CommandServerStop, CommandServerRestart;
private import odood.cli.commands.database: CommandDatabase, CommandDatabaseList;
private import odood.cli.commands.status: CommandStatus;


/** Custom logger for Odood CLI
  **/
class OdoodLogger : Logger {

    this(Args...)(auto ref Args args) { super(args); }

    override protected void writeLogMsg(ref LogEntry payload)
    {
        auto msg = escapeCCL(payload.msg);
        final switch (payload.logLevel) {
            case LogLevel.trace:
                cwritefln(
                    "<grey>TRACE</grey>: %s", msg);
                break;
            case LogLevel.info:
                cwritefln(
                    "<blue>INFO</blue>: %s", msg);
                break;
            case LogLevel.warning:
                cwritefln(
                    "<orange>WARNING</orange>: %s", msg);
                break;
            case LogLevel.error:
                cwritefln(
                    "<lred>ERROR</lred>: %s", msg);
                break;
            case LogLevel.critical:
                cwritefln(
                    "<red>CRITICAL</red>: %s", msg);
                break;
            case LogLevel.fatal:
                cwritefln(
                    "<lmagenta>FATAL</lmagenta>: %s", msg);
                break;
            case LogLevel.off, LogLevel.all:
                // No output; This log levels are not used in messages,
                // but just as filters.
                break;
        }
    }
}


class App: OdoodProgram {

    this() {
        super("odood", _version);
        this.summary("Easily manage odoo installations.");
        this.add(new CommandInit());
        this.add(new CommandServer());
        this.add(new CommandStatus());
        this.add(new CommandDatabase());

        // shortcuts
        this.add(new CommandServerStart());
        this.add(new CommandServerStop());
        this.add(new CommandServerRestart());
        this.add(new CommandDatabaseList("lsd"));

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
            errorf("Odood Exception catched: %s", e);
            return 1;
        } catch (Exception e) {
            errorf("Exception catched: %s", e);
            return 1;
        }
    }
}
