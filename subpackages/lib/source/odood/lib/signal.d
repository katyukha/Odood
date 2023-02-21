module odood.lib.signal;

private import core.sys.posix.signal;

private import std.logger;
private import std.exception;

private import odood.lib.exception: OdoodException;

private:
    __gshared bool _interrupted = false;
    __gshared bool _sigint_handler_set = false;

    sigaction_t oldSigIntAction;

	extern(C) void _sigIntHandler(int sig_number) nothrow {
		_interrupted = true;
	}

public:

    /** This exception will be raised on attempt to initialize signal handling
      * when it is already initialized
      **/
    class SignalHandlerAlreadySetError : OdoodException {
        mixin basicExceptionCtors;
    }

    /** This func could be used to check if keyboard interrupt happened
      **/
    @nogc nothrow const(bool) interrupted() {
        return _interrupted;
    }

    /** Initialize SIGINT handling.
      * This function will register custom sigint handler to automatically
      * set _interrupted variable to true when SIGINT received by app.
      *
      * Also, ensure that deinitSigIntHandling function called when signal
      * handling is not needed anymore.
      **/
    void initSigIntHandling() {
        if (_sigint_handler_set)
            throw new SignalHandlerAlreadySetError(
                "SIGINT Handler already set!");

        // Set global variable to indicate that signalling is registered
        _sigint_handler_set = true;

        sigaction_t handler;
        handler.sa_handler = &_sigIntHandler;
        handler.sa_mask = cast(sigset_t) 0;
        handler.sa_flags = 0;
        handler.sa_flags |= SA_RESTART;
        sigaction(SIGINT, &handler, &oldSigIntAction);
    }

    /** This function must be used to restore SIGINT handling
      * to previous value.
      **/
    void deinitSigIntHandling() {
        sigaction(SIGINT, &oldSigIntAction, null);
        _sigint_handler_set = false;
    }

