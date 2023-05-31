module odood.cli.core.exception;


/** This exception identifies, that in Odood program commandr Command
  * is used instead of OdoodCommand.
  * Currently, it is not allowed to mix odood commands and commandr commands
  * in one app
  **/
class OdoodCLICommandNoExecuteException : Exception {

    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}


class OdoodCLIExitException : Exception
{
    private int _exit_code;

    this(int exit_code=-1, string msg=null, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);

        _exit_code = exit_code;
    }

    pure int exit_code() const {
        return _exit_code;
    }
}



