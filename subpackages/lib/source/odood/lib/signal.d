module odood.lib.signal;

private import core.sys.posix.signal;

private import std.logger;
private import std.exception;
private import core.atomic : atomicOp, atomicLoad, atomicStore;

private import odood.exception: OdoodException;

private:
    shared bool _interrupted = false;
    shared uint _sigint_handler_counter = 0;

    __gshared sigaction_t oldSigIntAction;

	extern(C) void _sigIntHandler(int sig_number) nothrow {
		_interrupted.atomicStore(true);
	}

    /** Register SIGINT Handler.
      *
      * Private implementation.
      **/
    @trusted nothrow void _registerSigIntHandler() {
        sigaction_t handler;
        handler.sa_handler = &_sigIntHandler;
        handler.sa_mask = cast(sigset_t) 0;
        handler.sa_flags = 0;
        handler.sa_flags |= SA_RESTART;
        sigaction(SIGINT, &handler, &oldSigIntAction);
    }

    /** Unregister SIGINT Handler.
      *
      * Private implementation.
      **/
    @trusted nothrow void _unregisterSigIntHandler() {
        sigaction(SIGINT, &oldSigIntAction, null);
    }

public:
    /** This func could be used to check if keyboard interrupt happened
      **/
    @safe @nogc nothrow const(bool) interrupted() {
        return _interrupted;
    }

    /** Initialize SIGINT handling.
      * This function will register custom sigint handler to automatically
      * set _interrupted variable to true when SIGINT received by app.
      *
      * Also, ensure that deinitSigIntHandling function called when signal
      * handling is not needed anymore.
      **/
    @safe void initSigIntHandling() {
        if (_sigint_handler_counter.atomicLoad == 0) {
            _registerSigIntHandler;
        }

        // Set global variable to indicate that signalling is registered
        // Each time initSigIntHandling called, this counter will be increased.
        // Each time deinitSigIntHandling called, this counter will be
        // decreased.
        _sigint_handler_counter.atomicOp!"+="(1);

    }

    /** This function must be used to restore SIGINT handling
      * to previous value.
      **/
    @safe void deinitSigIntHandling() {
        _sigint_handler_counter.atomicOp!"-="(1);

        // Deinit SigInt handling only if it is last call to this method
        if (_sigint_handler_counter.atomicLoad == 0) {
            _unregisterSigIntHandler;
        }
    }

