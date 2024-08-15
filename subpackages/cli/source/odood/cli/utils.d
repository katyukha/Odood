module odood.cli.utils;

private import std.stdio: writefln;
private import std.conv: to;

private import odood.lib.odoo.log: OdooLogRecord;

private import colored;


/** Color log level, depending on log level itself
  *
  * Params:
  *     rec = OdooLogRecord, that represents single log statement
  * Returns:
  *     string that contains colored log level
  **/
auto colorLogLevel(in OdooLogRecord rec) {
    switch (rec.log_level) {
        case "DEBUG":
            return rec.log_level.bold.lightGray;
        case "INFO":
            return rec.log_level.bold.green;
        case "WARNING":
            return rec.log_level.bold.yellow;
        case "ERROR":
            return rec.log_level.bold.red;
        case "CRITICAL":
            return rec.log_level.bold.red;
        default:
            return rec.log_level.bold;
    }
}


/** Print single log record to stdout, applying colors
  **/
void printLogRecord(in OdooLogRecord rec) {
    writefln(
        "%s %s %s %s %s: %s",
        rec.date.lightBlue,
        rec.process_id.to!string.lightGray,
        rec.colorLogLevel,
        rec.db.cyan,
        rec.logger.magenta,
        rec.msg);
}


/** Print single log record to stdout in simplified form, applying colors
  **/
void printLogRecordSimplified(in OdooLogRecord rec) {
    import std.regex;

    immutable auto RE_LOG_RECORD_START = ctRegex!(
        r"(?P<date>\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\,\d{3})\s" ~
        r"(?P<processid>\d+)\s" ~
        r"(?P<loglevel>\S+)\s" ~
        r"(?P<db>\S+)\s" ~
        r"(?P<logger>\S+):\s(?=\`)");

    auto msg = rec.msg.replaceAll(
        RE_LOG_RECORD_START, "${loglevel} ${logger}: ");

    writefln(
        "%s %s: %s",
        rec.colorLogLevel,
        rec.logger.magenta,
        msg);
}


