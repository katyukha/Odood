module odood.lib.exception;


class OdoodException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}


class OdoodExitException : Exception
{
    private int _exit_code;

    this(int exit_code=-1, string msg=null, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
        
        _exit_code = exit_code;
    }

    @property pure int exit_code() const {
        return _exit_code;
    }
}
