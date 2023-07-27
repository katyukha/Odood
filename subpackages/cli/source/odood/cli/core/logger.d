module odood.cli.core.logger;

private import std.stdio;
private import std.logger;
private import std.format: format;

private import colored;


/** Custom logger for Odood CLI
  **/
class OdoodLogger : Logger {

    this(Args...)(auto ref Args args) { super(args); }

    // Trusted, because of using stderr, that uses __gshared under the hood
    override protected void writeLogMsg(ref LogEntry payload) @trusted
    {
        auto msg = payload.msg;
        final switch (payload.logLevel) {
            case LogLevel.trace:
                stderr.writeln("TRACE".darkGray, ": ", msg);
                break;
            case LogLevel.info:
                stderr.writeln("INFO".blue, ": ", msg);
                break;
            case LogLevel.warning:
                stderr.writeln("WARNING".yellow, ": ", msg);
                break;
            case LogLevel.error:
                stderr.writeln("ERROR".lightRed, ": ", msg);
                break;
            case LogLevel.critical:
                stderr.writeln("CRITICAL".red, ": ", msg);
                break;
            case LogLevel.fatal:
                stderr.writeln("FATAL".lightMagenta, ": ", msg);
                break;
            case LogLevel.off, LogLevel.all:
                // No output; This log levels are not used in messages,
                // but just as filters.
                break;
        }
    }
}
