module odood.cli.core.exception;

private import std.exception: basicExceptionCtors;


/** Base class for all Odood CLI exceptions
  **/
class OdoodCLIException : Exception {
    mixin basicExceptionCtors;
}


/** This exception identifies, that in Odood program commandr Command
  * is used instead of OdoodCommand.
  * Currently, it is not allowed to mix odood commands and commandr commands
  * in one app
  **/
class OdoodCLICommandNoExecuteException : OdoodCLIException {
    mixin basicExceptionCtors;
}


class OdoodCLIExitException : OdoodCLIException
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



