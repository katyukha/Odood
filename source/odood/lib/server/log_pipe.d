module odood.lib.server.log_pipe;

private static import std.process;
private import std.logger;
private import std.process: ProcessPipes, kill;
private import std.typecons: Nullable, nullable;
private import std.string: empty;

private import odood.lib.odoo.log: OdooLogProcessor, OdooLogRecord;


/** Struct to implement iterator (range) over log records captured
  * during server ran.
  **/
package struct OdooLogPipe {
    // TODO: May be it have sense to merge this struct with LogProcessor
    private:
        ProcessPipes _pipes;
        OdooLogProcessor _log_processor;
        bool _is_closed;
        Nullable!OdooLogRecord _log_record;
        int _exit_code; 

        void tryReadLogRecordIfNeeded() {
            if (!_log_record.isNull)
                // We already have log record in buffer, thus
                // there is no need to read new record.
                return;

            while (_log_record.isNull && !_is_closed) {
                string input = _pipes.stderr.readln();
                if (!input.empty)
                    _log_processor.feedInput(input);
                else {
                    // It seems that file is close, thus we have to
                    // wait the child process.
                    _exit_code = std.process.wait(_pipes.pid);       
                    _is_closed = true;
                    _log_processor.close();
                }
               _log_record = _log_processor.consumeRecord();
            }
        }

    package:
        this(ref ProcessPipes pipes) {
            _pipes = pipes;
        }
    public:
        /** This method have to be called to ensure that
          * the child process is exited and properly awaited by
          * parent process, to avoid zombies.
          * In case, if this struct used as range and completely
          * consumed, then it is not required to call this method.
          **/
        int close() {
            if (!_is_closed) {
                _exit_code = std.process.wait(_pipes.pid);
            }
            return _exit_code;
        }

        /** Return exit code of the process managed by this pipe
          **/
        @property int exit_code() const {
            return _exit_code;
        }

        @property bool empty() {
            tryReadLogRecordIfNeeded();
            return _log_record.isNull;
        }

        @property OdooLogRecord front() {
            tryReadLogRecordIfNeeded();
            return _log_record.get;
        }

        void popFront() {
            tryReadLogRecordIfNeeded();
            _log_record.nullify;
        }

        void kill() {
            _pipes.pid.kill();
        }
}


