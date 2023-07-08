module odood.lib.server.log_pipe;

private static import std.process;
private import std.logger;
private import std.process: ProcessPipes, kill;
private import std.typecons: Nullable, nullable;
private import std.string: empty;
private import std.format: format;
private import core.time;

private import odood.lib.odoo.log: OdooLogProcessor, OdooLogRecord;
private import odood.exception: OdoodException;


/** Struct to implement iterator (range) over log records captured
  * during server ran.
  **/
package struct OdooLogPipe {
    // TODO: May be it have sense to merge this struct with LogProcessor
    private:
        ProcessPipes _pipes;
        OdooLogProcessor _log_processor;

    package:
        this(ref ProcessPipes pipes) {
            _pipes = pipes;
            _log_processor = OdooLogProcessor(_pipes.stderr);
        }
    public:
        /** Check if log pipe is empty
          **/
        bool empty() { return _log_processor.empty; }

        /** Get current log record.
          **/
        OdooLogRecord front() { return _log_processor.front; }

        /** Pop current log record.
          **/
        void popFront() {
            _log_processor.popFront();
            if (_pipes.stderr.eof)
                wait();
        }

        /** Kill process this log is bound to
          *
          * Note, if you need exit code of the process killed, then
          * you have to pass false to wait param, and call wait separately.
          *
          * Params:
          *     wait = if set to true, then underlined process will be
          *         automatically awaited.
          **/
        void kill(in bool wait=true) {
            _pipes.pid.kill();
            if (wait)
                this.wait();
        }

        /** Wail process to complete.
          *
          * Returns: exit code of the process awaited.
          **/
        auto wait() {
            return std.process.wait(_pipes.pid);
        }
}


