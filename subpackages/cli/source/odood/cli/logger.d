module odood.cli.logger;

private import std.logger;
private import std.format: format;

private import consolecolors: cwritefln, escapeCCL;


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
