/// This module contains unilities for parsing odoo log output
module odood.lib.odoo.log;

private import std.logger;
private import std.exception: enforce;
private import std.string: join, empty;
private import std.regex;
private import std.conv: to;
private import std.format: format;
private import std.typecons: Nullable, nullable;
private import std.stdio: File;

private import odood.lib.exception: OdoodException;


/** Used to check if it is start of the log record
  **/
immutable auto RE_LOG_RECORD_START = ctRegex!(
    r"\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\,\d{3}\s\d+\s\S+\s\S+\s\S+:\s[^\`]");

/** Used to parse the log record
  **/
immutable auto RE_LOG_RECORD_DATA = ctRegex!(
    `^(?P<date>\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\,\d{3})\s` ~
    `(?P<process_id>\d+)\s` ~
    `(?P<log_level>\S+)\s` ~
    `(?P<db>\S+)\s` ~
    `(?P<logger>\S+):\s` ~
    `(?P<msg>[\s\S]*?)\n*$`);


/** This struct represents single log record
  **/
@safe struct OdooLogRecord {
    string date;
    ulong process_id;
    string log_level;
    string db;
    string logger;
    string msg;

    string full_str;

    ulong consumed_length;

    const(string) toString() const {
        import std.format: format;
        auto msg_truncated = msg.length > 200 ?
            (msg[0..200] ~ "...") : msg[0..$];
        return "%s %s %s %s %s %s".format(
            date, process_id, log_level, db, logger, msg_truncated);
    }
}


/** Struct that could be used for streaming log processing
  **/
@safe struct OdooLogProcessor {

    private File _source;
    private string _buffer="";
    private Nullable!OdooLogRecord _log_record;

    // Try to read next record fron log file
    private void tryReadLogRecordIfNeeded() {
        if (!_log_record.isNull)
            // We already have log record in buffer, thus
            // there is no need to read new record.
            return;

        if (_source.eof)
            // Ensure, that we will not try to read from the end of file.
            return;

        if (_buffer.empty) {
            // Skip everything before line start.
            // After this code ran, buffer will contain first line of
            // record to be read
            while (_buffer.empty && !_source.eof) {
                string line = (() @trusted => _source.readln())();

                if (line.matchFirst(RE_LOG_RECORD_START)) {
                    _buffer = line;
                    break;
                } else {
                    debug warningf(
                        "Skipping unparsed log content: '%s'", line);
                }
            }

            if (_buffer.empty)
                // We did not find anything suitable to parse, so return.
                return;
        }

        // Read next line, in attempt to find the start of next log line
        string line_read;
        do {
            line_read = (() @trusted => _source.readln())();

            if (line_read.empty || line_read.matchFirst(RE_LOG_RECORD_START)) {
                // Here we can assume that everything that is in the buffer
                // represent complete single log record, so we can parse it,
                // and store in _log_record and place 'line_read'
                // in buffer instead.
                auto captures = _buffer.matchFirst(RE_LOG_RECORD_DATA);

                enforce!OdoodException(
                    captures,
                    "Cannot parse buffer:\n%s\n---".format(_buffer));

                // Create resulting log record
                OdooLogRecord res;
                res.date = captures["date"];
                res.process_id = captures["process_id"].to!ulong;
                res.log_level = captures["log_level"];
                res.db = captures["db"];
                res.logger = captures["logger"];
                res.msg = captures["msg"];
                res.full_str = captures.hit;

                // Save this record as current in processor
                _log_record = res.nullable;

                // Save line_read in buffer;
                _buffer = line_read;
            } else {
                // It is not the new line, thus we can add it to buffer for
                // futher processing
                _buffer ~= line_read;
            }

        } while (!_source.eof && _log_record.isNull);
    }

    /** Create new instance of log processor attached to specified file.
      **/
    this(File f) {
        _source = f;
    }

    /// Allows to check if processor is closed for new input or not.
    @property bool isClosed() const {
        return _source.eof;
    }

    /// Check if there is no more input to handle
    @property bool empty() const {
        return _source.eof;
    }

    /// Get front record
    @property OdooLogRecord front() {
        tryReadLogRecordIfNeeded();
        return _log_record.get;
    }

    /// Pop front record
    void popFront() {
        tryReadLogRecordIfNeeded();
        _log_record.nullify;
    }
}


///
unittest {
    import unit_threaded.assertions;

    auto f = File("test-data/odoo.test.1.log", "rt");
    auto processor = OdooLogProcessor(f);

    processor.front.msg.shouldEqual("Odoo version 15.0");
    processor.popFront;
    processor.front.msg.shouldEqual("skip sending email in test mode");
    processor.popFront;
    processor.front.msg.shouldEqual("Starting TestRequestBase.test_request_author_changed_event_created ... ");
    processor.popFront;
    processor.front.msg.shouldEqual("====================================================================== ");
    processor.popFront;
    processor.front.msg.shouldEqual("FAIL: TestRequestBase.test_request_author_changed_event_created
Traceback (most recent call last):
  File \"/data/projects/odoo/odood-15.0-ag/custom_addons/generic_request/tests/test_request.py\", line 828, in test_request_author_changed_event_created
    self.assertEqual(request.request_event_count, 1)
AssertionError: 2 != 1");
    processor.popFront;
    processor.front.msg.shouldEqual("Starting TestRequestBase.test_request_can_change_category ... ");
    processor.empty.shouldBeTrue();
}

unittest {
    import unit_threaded.assertions;

    auto f = File("test-data/odoo.test.2.log", "rt");
    auto processor = OdooLogProcessor(f);

    OdooLogRecord[] records = [];

    processor.front.msg.shouldEqual("Odoo version 12.0 ");

    foreach(ref record; processor)
        records ~= record;

    processor.isClosed.shouldBeTrue;

    records[$-1].msg.shouldEqual("Hit CTRL-C again or send a second signal to force the shutdown. ");
    records.length.shouldEqual(229);
}

unittest {
    import std.algorithm.searching: startsWith;
    import unit_threaded.assertions;

    auto f = File("test-data/odoo.test.3.log", "rt");
    auto processor = OdooLogProcessor(f);

    OdooLogRecord[] records = [];

    processor.front.msg.startsWith("Traceback (most recent call last): ").shouldBeTrue;

    foreach(ref record; processor)
        records ~= record;

    processor.isClosed.shouldBeTrue;
    records[$-1].msg.shouldEqual(
        "test_onchange_contract_restrict_service_clean_service (odoo.addons.generic_request_contract.tests.test_generic_request_contract_service.TestRequestContractService) ");
    records.length.shouldEqual(15);
}
