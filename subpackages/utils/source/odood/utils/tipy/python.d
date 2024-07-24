module odood.utils.tipy.python;

private import bindbc.common.codegen: joinFnBinds, FnBind;

// Copied from python
enum Py_single_input = 256;
enum Py_file_input = 257;
enum Py_eval_input = 258;
enum Py_func_type_input = 345;

// Dummy structure to represent pointer to python object
struct PyObject {};

// Dummy structure to represent pointer to pythons thread state
struct PyThreadState {};

// Copied from python pystate.h
enum PyGILState_STATE {
    PyGILState_LOCKED,
    PyGILState_UNLOCKED,
};

alias Py_ssize_t = size_t;


mixin(joinFnBinds!false((){
    FnBind[] ret = [
        // General
        {q{void}, q{Py_Initialize}},
        {q{void}, q{PyEval_InitThreads}},
        {q{int}, q{PyEval_ThreadsInitialized}},
        {q{PyThreadState*}, q{PyEval_SaveThread}},
        {q{void}, q{PyEval_RestoreThread}, q{PyThreadState *tstate}},
        {q{void}, q{Py_Finalize}},
        {q{void}, q{Py_DecRef}, q{PyObject* o}},

        // GIL
        {q{PyGILState_STATE}, q{PyGILState_Ensure}},
        {q{void}, q{PyGILState_Release}, q{PyGILState_STATE}},


        // Import & module
        {q{PyObject*}, q{PyImport_ImportModule}, q{const char* name}},
        {q{PyObject*}, q{PyModule_GetDict}, q{PyObject* mod}},

        //PyErr
        {q{PyObject*}, q{PyErr_Occurred}},
        {q{void}, q{PyErr_Fetch}, q{PyObject **ptype, PyObject **pvalue, PyObject **ptraceback}},

        // PyDict
        {q{PyObject*}, q{PyDict_New}},
        {q{PyObject*}, q{PyDict_GetItemString}, q{PyObject* p, const char* key}},  // returns Borrowed reference

        // PyTuple
        {q{PyObject*}, q{PyTuple_New}, q{Py_ssize_t len}},
        {q{PyObject*}, q{PyTuple_SetItem}, q{PyObject* p, Py_ssize_t pos, PyObject* o}},

        // PyObject
        {q{PyObject*}, q{PyObject_Str}, q{PyObject* o}},
        {q{PyObject*}, q{PyObject_Call}, q{PyObject* callable, PyObject* args, PyObject* kwargs}},
        {q{PyObject*}, q{PyObject_CallObject}, q{PyObject* callable, PyObject* args}},
        {q{PyObject*}, q{PyObject_Type}, q{PyObject* o}},
        {q{PyObject*}, q{PyObject_GetAttrString}, q{PyObject* o, const char* attr_name}},
        {q{PyObject*}, q{PyObject_GetIter}, q{PyObject* o}},
        {q{int}, q{PyObject_IsTrue}, q{PyObject* o}},
        {q{int}, q{PyObject_IsInstance}, q{PyObject* inst, PyObject* cls}},

        // PyIter
        {q{PyObject*}, q{PyIter_Next}, q{PyObject* o}},

        // PyList
        {q{PyObject*}, q{PyList_AsTuple}, q{PyObject* list}},

        // PyBytes
        {q{char*}, q{PyBytes_AsString}, q{PyObject* o}},

        // PyUnicode
        {q{PyObject*}, q{PyUnicode_AsUTF8String}, q{PyObject* unicode}},
        {q{PyObject*}, q{PyUnicode_FromString}, q{const char*}},

        // PyFloat
        {q{double}, q{PyFloat_AsDouble}, q{PyObject* pyfloat}},

        // PyLong
        {q{double}, q{PyLong_AsDouble}, q{PyObject* pylong}},
        {q{PyObject*}, q{PyLong_FromLongLong}, q{long v}},
        {q{long}, q{PyLong_AsLongLong}, q{PyObject* pylong}},

        // PyNumber
        {q{PyObject*}, q{PyNumber_Float}, q{PyObject* o}},
    ];
    // See: https://github.com/BindBC/bindbc-freetype/blob/master/source/ft/advanc.d
    return ret;
}()));


