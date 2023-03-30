module odood.cli.core.logger;

private import std.stdio;
private import std.logger;
private import std.format: format;

private import colored;


/** Custom logger for Odood CLI
  **/
class OdoodLogger : Logger {

    this(Args...)(auto ref Args args) { super(args); }

    override protected void writeLogMsg(ref LogEntry payload)
    {
        auto msg = payload.msg;
        final switch (payload.logLevel) {
            case LogLevel.trace:
                writeln("TRACE".darkGray, ": ", msg);
                break;
            case LogLevel.info:
                writeln("INFO".blue, ": ", msg);
                break;
            case LogLevel.warning:
                writeln("WARNING".yellow, ": ", msg);
                break;
            case LogLevel.error:
                writeln("ERROR".lightRed, ": ", msg);
                break;
            case LogLevel.critical:
                writeln("CRITICAL".red, ": ", msg);
                break;
            case LogLevel.fatal:
                writeln("FATAL".lightMagenta, ": ", msg);
                break;
            case LogLevel.off, LogLevel.all:
                // No output; This log levels are not used in messages,
                // but just as filters.
                break;
        }
    }
}
