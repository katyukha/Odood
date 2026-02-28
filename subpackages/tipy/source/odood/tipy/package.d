module odood.tipy;

private import std.string;
private import std.traits:
    isSomeString, isScalarType, isIntegral, isBoolean, isFloatingPoint, isArray;
private import std.range: ElementType, iota;


private static import bindbc.loader;
private import odood.tipy.python;


// Loaded library
private bindbc.loader.SharedLib pylib;


private static enum supported_lib_names = mixin(bindbc.loader.makeLibPaths(
    names: [
        "python3.14",
        "python3.13",
        "python3.12",
        "python3.11",
        "python3.10",
        "python3.9",
        "python3.8",
        "python3.7",
        "python3.6",
    ],
    platformPaths: [
        "OSX": [
            // Search for homebrew paths for python13 on MacOS
            "/opt/homebrew/opt/python@3.14/Frameworks/Python.framework/Versions/3.14/lib/",
            "/usr/local/opt/python@3.14/Frameworks/Python.framework/Versions/3.14/lib/",
            "/opt/homebrew/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/lib/",
            "/usr/local/opt/python@3.13/Frameworks/Python.framework/Versions/3.13/lib/",
            "/opt/homebrew/opt/python@3.12/Frameworks/Python.framework/Versions/3.12/lib/",
            "/usr/local/opt/python@3.12/Frameworks/Python.framework/Versions/3.12/lib/",
        ],
    ]
));


// Python runtime lifecycle state
private shared PyThreadState* _py_thread_state = null;
private shared bool _py_initialized = false;


// Boot the Python runtime: load the shared library, initialize the
// interpreter, enable threading support, and release the GIL.
// Returns true on success; throws on failure.
private bool initPyRuntime() {
    import bindbc.loader;
    import std.algorithm: map;
    import std.format: format;
    import std.string: fromStringz, join;

    auto err_count_start = bindbc.loader.errorCount;
    if (!loadPyLib()) {
        auto errors = bindbc.loader.errors[err_count_start .. bindbc.loader.errorCount]
            .map!((e) => "%s: %s".format(e.error.fromStringz.idup, e.message.fromStringz.idup))
            .join(",\n");
        throw new Exception("Cannot load python as library! Errors: %s".format(errors));
    }

    Py_Initialize();
    if (!PyEval_ThreadsInitialized())
        PyEval_InitThreads();

    _py_thread_state = cast(shared PyThreadState*) PyEval_SaveThread();
    return true;
}


/** Ensure the Python runtime is loaded and initialized exactly once.
  * Thread-safe via initOnce (double-checked locking).
  * Subsequent calls after the first are no-ops.
  **/
void ensurePyInitialized() {
    import std.concurrency: initOnce;
    initOnce!_py_initialized(initPyRuntime());
}


// Shut down the Python runtime at program exit.
shared static ~this() {
    if (_py_thread_state)
        PyEval_RestoreThread(cast(PyThreadState*) _py_thread_state);
    if (_py_initialized)
        Py_Finalize();
}


// Load python library
bool loadPyLib() {
    foreach(libname; supported_lib_names) {
        pylib = bindbc.loader.load(libname.ptr);
        if (pylib == bindbc.loader.invalidHandle) {
            continue;
        }

        const auto err_count = bindbc.loader.errorCount;
        odood.tipy.python.bindModuleSymbols(pylib);
        if (bindbc.loader.errorCount == err_count)
            return true;
    }

    // Cannot load library
    return false;
}


/** Low-level string extraction that does NOT call pyEnforce or pyEnsureNoError.
  * Used inside error-handling paths to avoid infinite recursion.
  * On any nested failure, clears the error and returns a fallback string.
  **/
private string pyObjectToStringRaw(PyObject* o) {
    if (!o) return "<null>";
    auto unicode = PyObject_Str(o);
    if (!unicode) { PyErr_Clear(); return "<failed to stringify>"; }
    scope(exit) Py_DecRef(unicode);
    auto str = PyUnicode_AsUTF8String(unicode);
    if (!str) { PyErr_Clear(); return "<failed to encode>"; }
    scope(exit) Py_DecRef(str);
    auto cstr = PyBytes_AsString(str);
    if (!cstr) { PyErr_Clear(); return "<failed to get bytes>"; }
    return cstr.fromStringz.idup;
}


/** Ensure no python error is set.
  * Checks python error indicator and throw error if such indicator is set.
  *
  * Throws:
  *     Exception when python object is not valid and some error occured.
  **/
void pyEnsureNoError() {
    if (PyErr_Occurred()) {
        PyObject* etype=null, evalue=null, etraceback=null;
        PyErr_Fetch(&etype, &evalue, &etraceback);
        scope(exit) {
            if (etype) Py_DecRef(etype);
            if (evalue) Py_DecRef(evalue);
            if (etraceback) Py_DecRef(etraceback);
        }

        string msg = pyObjectToStringRaw(etype);
        if (evalue) msg ~= ": " ~ pyObjectToStringRaw(evalue);
        throw new Exception(msg);
    }
}


/** Ensure that pyobjec is valid and no error is produced
  *
  * Params:
  *     value = python object to validate
  *
  * Returns:
  *     value if it is valid, otherwise throws error
  *
  * Throws:
  *     Exception when python object is not valid and some error occured.
  **/
auto pyEnforce(PyObject* value) {
    if (!value) {
        pyEnsureNoError();
        throw new Exception("Python returned NULL without setting an error indicator");
    }
    return value;
}


/** Convert python object to D representation.
  **/
T convertPyToD(T)(PyObject* o)
if (isSomeString!T) {
    auto unicode = PyObject_Str(o).pyEnforce;
    scope(exit) Py_DecRef(unicode);
    auto str = PyUnicode_AsUTF8String(unicode).pyEnforce;
    scope(exit) Py_DecRef(str);
    return PyBytes_AsString(str).fromStringz.idup;
}


/// ditto
T convertPyToD(T)(PyObject* o)
if (isBoolean!T) {
    const int result = PyObject_IsTrue(o);
    switch(result) {
        case 1: return true;
        case 0: return false;
        case -1:
            // Error. Pass null explicitely to enforce checking error
            // info and raising exception.
            pyEnsureNoError();
            throw new Exception("Cannot convert py object to bool for unknown reason");
        default:
            assert(0, "Unsupported return value from PyObject_IsTrue");
    }
}

/// ditto
T convertPyToD(T)(PyObject* o)
if (isArray!T && !isSomeString!T) {
    T result;
    auto iterator = PyObject_GetIter(o).pyEnforce;
    scope(exit) Py_DecRef(iterator);

    while(auto item = PyIter_Next(iterator)) {
        scope(exit) Py_DecRef(item);
        result ~= convertPyToD!(ElementType!T)(item);
    }

    // Ensure python error indicator is not set
    pyEnsureNoError();

    return result;
}

/// ditto
T convertPyToD(T)(PyObject* o)
if (isFloatingPoint!T) {
    auto number = PyNumber_Float(o).pyEnforce;
    const double result = PyFloat_AsDouble(number);
    pyEnsureNoError();
    return result;
}


/** Convert to python object
  *
  * Params:
  *     val = value to convert to python object
  * Returns:
  *     Pointer to new reference to PyObject.
  **/
PyObject* convertToPy(T)(T val) {
    static if(isIntegral!T)
        return PyLong_FromLongLong(val);
    else static if (isSomeString!T)
        return PyUnicode_FromString(val.toStringz);
    else
        static assert(0, "Unsupported type");
}


/** Call python function with arguments
  *
  * Params:
  *     fn = python object that represents function to call
  *     params = D variadic parameters to pass to function
  * Returns:
  *     PyObject pointer that represents result of function execution
  **/
auto callPyFunc(T...)(PyObject* fn, T params) {
    auto args = PyTuple_New(T.length);
    scope(exit) Py_DecRef(args);

    auto kwargs = PyDict_New();
    scope(exit) Py_DecRef(kwargs);

    static foreach(i; iota(0, T.length)) {
        // There is no nees to decref, because SetItem steals ref
        PyTuple_SetItem(args, i, params[i].convertToPy);
    }

    return PyObject_Call(fn, args, kwargs).pyEnforce;
}
