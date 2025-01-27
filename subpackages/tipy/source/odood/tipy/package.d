module odood.tipy;

private import std.string;
private import std.traits:
    isSomeString, isScalarType, isIntegral, isBoolean, isFloatingPoint, isArray;
private import std.range: ElementType, iota;


private static import bindbc.loader;
private import odood.tipy.python;


// Loaded library
private bindbc.loader.SharedLib pylib;


private static enum supported_lib_names = mixin(bindbc.loader.makeLibPaths([
    "python3.13",
    "python3.12",
    "python3.11",
    "python3.10",
    "python3.9",
    "python3.8",
    "python3.7",
    "python3.6",
    "python3.5",
    "python3.4",
    "python3.3",
]));


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

        // TODO: Think about avoiding usage of convertPyToD
        //       to avoid possible infinite recursion
        string msg = etype.convertPyToD!string;
        if (evalue) msg ~= ": " ~ evalue.convertPyToD!string;
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
    if (!value)
       pyEnsureNoError();
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

    // Ensure python error indicatori is not set
    pyEnsureNoError();

    return result;
}

/// ditto
T convertPyToD(T)(PyObject* o)
if (isFloatingPoint!T) {
    auto number = PyNumber_Float(o).pyEnforce;
    const double result = PyFloat_AsDouble(number);
    pyEnsureNoError;
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

    //writefln("Call fn %s with args %s and kwargs %s", convertPyToString(fn), convertPyToString(args), convertPyToString(kwargs));
    auto res = PyObject_Call(fn, args, kwargs);
    pyEnforce(res);
    //writefln("Result: %s", res.convertPyToString);
    return res;
}
