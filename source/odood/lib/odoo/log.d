/// This module contains unilities for parsing odoo log output
module odood.lib.odoo.log;

private import std.logger;
private import std.exception: enforce;
private import std.string: join, empty;
private import std.regex;
private import std.conv: to;
private import std.typecons: Nullable, nullable;

private import odood.lib.exception: OdoodException;


/// Regex to parse odoo Line (match all text before next log record
immutable auto RE_PARSE_ODOO_LOG = ctRegex!(
    `(?P<date>\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d\,\d\d\d)\s` ~
    `(?P<process_id>\d+)\s` ~
    `(?P<log_level>[A-Z]+)\s` ~
    `(?P<db>\?|[\w\-_]+)\s` ~
    `(?P<logger>[\w\.]+):\s` ~
    `(?P<msg>[\s\S]*?)\n*` ~
    `(?=(\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d\,\d\d\d\s\d+\s[A-Z]+\s))`,
    "gs");

/// Same as previous but mutches log entry before end of input
immutable auto RE_PARSE_ODOO_LOG_E = ctRegex!(
    `(?P<date>\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d\,\d\d\d)\s` ~
    `(?P<process_id>\d+)\s` ~
    `(?P<log_level>[A-Z]+)\s` ~
    `(?P<db>\?|[\w\-_]+)\s` ~
    `(?P<logger>[\w\.]+):\s` ~
    `(?P<msg>[\s\S]*?)\n*` ~
    `(?=$)`,
    "gs");

/** Same as previous, but matches log entry that ends with start of
  * next log entry or end of input
  **/
immutable auto RE_PARSE_ODOO_LOG_G = ctRegex!(
    `(?P<date>\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d\,\d\d\d)\s` ~
    `(?P<process_id>\d+)\s` ~
    `(?P<log_level>[A-Z]+)\s` ~
    `(?P<db>\?|[\w\-_]+)\s` ~
    `(?P<logger>[\w\.]+):\s` ~
    `(?P<msg>[\s\S]*?)\n*` ~
    `(?=(\d\d\d\d-\d\d-\d\d\s\d\d:\d\d:\d\d\,\d\d\d\s\d+\s[A-Z]+\s)|$)`,
    "gs");

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
}


/** Struct that could be used for streaming log processing
  **/
@safe struct OdooLogProcessor {

    private string _buffer="";
    private bool _closed=false;

    this(in string buffer, in bool close=false) {
        _buffer = buffer;
        _closed = close;
    }

    /// Current content of processor's buffer
    @property const(string) buffer() const {
        return _buffer;
    }

    /// Allows to check if processor is closed for new input or not.
    @property bool isClosed() const {
        return _closed;
    }

    /** Add some new input to processor.
      * This method could be called multiple times to fed processor with
      * chunks for text.
      **/
    void feedInput(in string input)
    in {
        assert (_closed == false, "Cannot modify closed log processor");
    } do {
        _buffer ~= input;
    }

    /** Add new line to the processor.
      * It is same as feedInput, but automatically adds '\n'
      * to the end of line.
      **/
    void feedLine(in string line) 
    in {
        assert (_closed == false, "Cannot modify closed log processor");
    } do {
        feedInput(line ~ "\n");
    }

    /** Close processor. This means that no new input could be fed to
      * processor.
      **/
    void close() {
        enforce!OdoodException(
            !_closed,
            "OdooLogProcessor already closed");
        _closed = true;
    }

    // Check if processor is empty
    bool empty() const {
        return _buffer.empty;
    }

    /** Consume single record from this processor.
      * If record could not be consumed, then null will be returned
      **/
    Nullable!OdooLogRecord consumeRecord() {
        if (_buffer.empty)
            // Buffer is empty
            return Nullable!OdooLogRecord.init;  // Return null

        auto c = _closed ?
            _buffer.matchFirst(RE_PARSE_ODOO_LOG_G) :
            _buffer.matchFirst(RE_PARSE_ODOO_LOG);

        if (c.empty)
            // No match found in input
            return Nullable!OdooLogRecord.init;  // Return null

        if (!_closed && c.post.empty)
            /* If there is no unparsed data,
             * then it seems that record is not complete.
             * Thus we have to return null and
             * try to parse it one more time when we get more input.
             */
            return Nullable!OdooLogRecord.init;

        OdooLogRecord res;
        res.date = c["date"];
        res.process_id = c["process_id"].to!ulong;
        res.log_level = c["log_level"];
        res.db = c["db"];
        res.logger = c["logger"];
        res.msg = c["msg"];
        res.full_str = c.hit;

        res.consumed_length = c.pre.length + c.hit.length;

        warningf(
            c.pre.length > 0 && c.pre != "\n",
            "Consumed unparsed log data %s", c.pre);

        // Remove parsed record from buffer
        _buffer = _buffer[res.consumed_length .. $];

        return res.nullable;
    }
}


///
unittest {
    import unit_threaded.assertions;

    // Create processor based on full log. Thus we create it already closed.
    auto processor = OdooLogProcessor("
2023-01-02 15:34:15,656 115109 INFO ? odoo: Odoo version 15.0
2023-01-02 15:34:22,452 115109 INFO odood15-ag-1 odoo.tests: skip sending email in test mode
2023-01-02 15:34:26,872 115109 INFO odood15-ag-1 odoo.addons.generic_request.tests.test_request: Starting TestRequestBase.test_request_author_changed_event_created ... 
2023-01-02 15:34:26,873 115109 INFO odood15-ag-1 odoo.addons.generic_request.tests.test_request: ====================================================================== 
2023-01-02 15:34:26,873 115109 ERROR odood15-ag-1 odoo.addons.generic_request.tests.test_request: FAIL: TestRequestBase.test_request_author_changed_event_created
Traceback (most recent call last):
  File \"/data/projects/odoo/odood-15.0-ag/custom_addons/generic_request/tests/test_request.py\", line 828, in test_request_author_changed_event_created
    self.assertEqual(request.request_event_count, 1)
AssertionError: 2 != 1

2023-01-02 15:34:26,874 115109 INFO odood15-ag-1 odoo.addons.generic_request.tests.test_request: Starting TestRequestBase.test_request_can_change_category ... 
", true);
    processor.consumeRecord().get.msg.shouldEqual("Odoo version 15.0");
    processor.consumeRecord().get.msg.shouldEqual("skip sending email in test mode");
    processor.consumeRecord().get.msg.shouldEqual("Starting TestRequestBase.test_request_author_changed_event_created ... ");
    processor.consumeRecord().get.msg.shouldEqual("====================================================================== ");
    processor.consumeRecord().get.msg.shouldEqual("FAIL: TestRequestBase.test_request_author_changed_event_created
Traceback (most recent call last):
  File \"/data/projects/odoo/odood-15.0-ag/custom_addons/generic_request/tests/test_request.py\", line 828, in test_request_author_changed_event_created
    self.assertEqual(request.request_event_count, 1)
AssertionError: 2 != 1");
    processor.consumeRecord().get.msg.shouldEqual("Starting TestRequestBase.test_request_can_change_category ... ");
}

///
unittest {
    import unit_threaded.assertions;

    auto processor = OdooLogProcessor();
    processor.consumeRecord().isNull.shouldBeTrue;

    processor.feedLine(
            "2023-01-02 15:34:15,656 115109 INFO ? odoo: Odoo version 15.0");

    // Because it is steaming processing, we do not know
    // if we got full info about log record
    processor.consumeRecord().isNull.shouldBeTrue;

    processor.feedLine(
            "2023-01-02 15:34:22,452 115109 INFO odood15-ag-1 odoo.tests: skip sending email in test mode");

    // Consume record returns previous record
    processor.consumeRecord().get.msg.shouldEqual("Odoo version 15.0");

    processor.feedLine("2023-01-02 15:34:26,872 115109 INFO odood15-ag-1 odoo.addons.generic_request.tests.test_request: Starting TestRequestBase.test_request_author_changed_event_created ... ");
    processor.consumeRecord().get.msg.shouldEqual("skip sending email in test mode");

    processor.feedLine("2023-01-02 15:34:26,873 115109 INFO odood15-ag-1 odoo.addons.generic_request.tests.test_request: ====================================================================== ");
    processor.consumeRecord().get.msg.shouldEqual("Starting TestRequestBase.test_request_author_changed_event_created ... ");
    
    processor.feedLine("2023-01-02 15:34:26,873 115109 ERROR odood15-ag-1 odoo.addons.generic_request.tests.test_request: FAIL: TestRequestBase.test_request_author_changed_event_created");
    processor.consumeRecord().get.msg.shouldEqual("====================================================================== ");

    processor.feedLine("Traceback (most recent call last):");
    processor.consumeRecord().isNull.shouldBeTrue;
  
    processor.feedLine("  File \"/data/projects/odoo/odood-15.0-ag/custom_addons/generic_request/tests/test_request.py\", line 828, in test_request_author_changed_event_created");
    processor.consumeRecord().isNull.shouldBeTrue;
 
    processor.feedLine("    self.assertEqual(request.request_event_count, 1)");
    processor.consumeRecord().isNull.shouldBeTrue;

    processor.feedLine("AssertionError: 2 != 1");
    processor.consumeRecord().isNull.shouldBeTrue;

    processor.feedLine("");
    processor.consumeRecord().isNull.shouldBeTrue;

    processor.feedLine("2023-01-02 15:34:26,874 115109 INFO odood15-ag-1 odoo.addons.generic_request.tests.test_request: Starting TestRequestBase.test_request_can_change_category ... ");
    processor.consumeRecord().get.msg.shouldEqual("FAIL: TestRequestBase.test_request_author_changed_event_created
Traceback (most recent call last):
  File \"/data/projects/odoo/odood-15.0-ag/custom_addons/generic_request/tests/test_request.py\", line 828, in test_request_author_changed_event_created
    self.assertEqual(request.request_event_count, 1)
AssertionError: 2 != 1");

    processor.consumeRecord().isNull.shouldBeTrue;

    // After we closed processor, we could read last line
    processor.close();
    processor.consumeRecord().get.msg.shouldEqual("Starting TestRequestBase.test_request_can_change_category ... ");

    // No new lines expected
    processor.consumeRecord().isNull.shouldBeTrue;
}
