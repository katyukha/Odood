module odood.utils.addons.addon_manifest;

private import std.exception: enforce;
private import std.format: format;
private import std.string: toStringz;

private import thepath: Path;

private import odood.tipy;
private import odood.tipy.python;

private import odood.exception: OdoodException;
private import odood.utils.odoo.std_version;


/** Struct designed to read addons manifest
  **/
struct OdooAddonManifest {

    /** Use separate struct to handle prices
      * The default currency is EUR
      *
      * Additionally, this struct contains field is_set, that determines
      * if price was set in manifest or not (even if price is 0).
      **/
    private struct ManifestPrice {
        string currency;
        float price;
        bool is_set = false;

        string toString() const {
            if (is_set)
                return "%s %s".format(price, currency);
            return "";
        }
    }

    string name;
    string summary;
    OdooStdVersion module_version = OdooStdVersion("1.0");
    string author;
    string category;
    string description;
    string license="LGPL-3";
    string maintainer;

    bool auto_install=false;
    bool application=false;
    bool installable=true;

    // Dependencies
    string[] dependencies;
    string[] python_dependencies;
    string[] bin_dependencies;

    // CR&D Extensions
    string[] tags;

    ManifestPrice price;

    /// Return string representation of manifest
    string toString() const {
        return "AddonManifest: %s (%s)".format(name, module_version);
    }
}

/** Parse Odoo manifest file
  **/
auto parseOdooManifest(in string manifest_content) {
    OdooAddonManifest manifest;

    // Acuire python's GIL
    auto gstate = PyGILState_Ensure();
    scope(exit) PyGILState_Release(gstate);

    auto parsed = callPyFunc(cast(PyObject*)_fn_literal_eval, manifest_content);
    scope(exit) Py_DecRef(parsed);

    // PyDict_GetItemString returns borrowed reference,
    // thus there is no need to call Py_DecRef from our side
    if (auto val = PyDict_GetItemString(parsed, "name".toStringz))
        manifest.name = val.convertPyToD!string;
    if (auto val = PyDict_GetItemString(parsed, "summary".toStringz))
        manifest.summary = val.convertPyToD!string;
    if (auto val = PyDict_GetItemString(parsed, "version".toStringz))
        manifest.module_version = OdooStdVersion(val.convertPyToD!string);
    if (auto val = PyDict_GetItemString(parsed, "author".toStringz))
        manifest.author = val.convertPyToD!string;
    if (auto val = PyDict_GetItemString(parsed, "category".toStringz))
        manifest.category = val.convertPyToD!string;
    if (auto val = PyDict_GetItemString(parsed, "description".toStringz))
        manifest.description = val.convertPyToD!string;
    if (auto val = PyDict_GetItemString(parsed, "license".toStringz))
        manifest.license = val.convertPyToD!string;
    if (auto val = PyDict_GetItemString(parsed, "maintainer".toStringz))
        manifest.maintainer = val.convertPyToD!string;

    if (auto val = PyDict_GetItemString(parsed, "auto_install".toStringz))
        manifest.auto_install = val.convertPyToD!bool;
    if (auto val = PyDict_GetItemString(parsed, "application".toStringz))
        manifest.application = val.convertPyToD!bool;
    if (auto val = PyDict_GetItemString(parsed, "installable".toStringz))
        manifest.installable = val.convertPyToD!bool;

    if (auto val = PyDict_GetItemString(parsed, "depends".toStringz))
        manifest.dependencies = val.convertPyToD!(string[]);
    if (auto external_deps = PyDict_GetItemString(parsed, "external_dependencies".toStringz)) {
        if (auto val = PyDict_GetItemString(external_deps, "python".toStringz))
            manifest.python_dependencies = val.convertPyToD!(string[]);
        if (auto val = PyDict_GetItemString(external_deps, "bin".toStringz))
            manifest.bin_dependencies = val.convertPyToD!(string[]);
    }

    if (auto val = PyDict_GetItemString(parsed, "tags".toStringz))
        manifest.tags = val.convertPyToD!(string[]);


    if (auto py_price = PyDict_GetItemString(parsed, "price".toStringz)) {
        manifest.price.price = py_price.convertPyToD!float;

        if (auto py_currency = PyDict_GetItemString(parsed, "currency".toStringz)) {
            manifest.price.currency = py_currency.convertPyToD!string;
        } else {
            manifest.price.currency = "EUR";
        }

        manifest.price.is_set = true;
    }

    return manifest;
}

/// ditto
auto parseOdooManifest(in Path path) {
    return parseOdooManifest(path.readFileText);
}

// Module level link to ast module
private shared PyObject* _fn_literal_eval;
private shared PyThreadState* _py_thread_state;
private shared bool _py_initialized = false;

// Initialize python interpreter (import ast.literal_eval)
shared static this() {
    // TODO: think about lazy initialization of python
    import bindbc.loader;
    import std.algorithm: map;
    import std.string: fromStringz, join;

    auto err_count_start = bindbc.loader.errorCount;
    bool load_status = loadPyLib;
    if (!load_status) {
        auto errors = bindbc.loader.errors[err_count_start .. bindbc.loader.errorCount]
            .map!((e) => "%s: %s".format(e.error.fromStringz.idup, e.message.fromStringz.idup))
            .join(",\n");
        throw new OdoodException("Cannot load python as library! Errors: %s".format(errors));
    }

    Py_Initialize();
    if (!PyEval_ThreadsInitialized())
        PyEval_InitThreads();

    auto mod_ast = PyImport_ImportModule("ast");
    scope(exit) Py_DecRef(mod_ast);

    // Save function literal_eval from ast on module level
    _fn_literal_eval = cast(shared PyObject*)PyObject_GetAttrString(
        mod_ast, "literal_eval".toStringz
    ).pyEnforce;

    _py_thread_state = cast(shared PyThreadState*)PyEval_SaveThread();
    _py_initialized = cast(shared bool)true;
}

// Finalize python interpreter (do clean up)
shared static ~this() {
    if (_py_thread_state)
        PyEval_RestoreThread(cast(PyThreadState*)_py_thread_state);
    if (_fn_literal_eval)
        Py_DecRef(cast(PyObject*)_fn_literal_eval);
    if (_py_initialized)
        Py_Finalize();
}


// Tests
unittest {
    const auto manifest = parseOdooManifest(`{
    'name': "A Module",
    'version': '1.0',
    'depends': ['base'],
    'author': "Author Name",
    'category': 'Category',
    'description': """
    Description text
    """,
    # data files always loaded at installation
    'data': [
        'views/mymodule_view.xml',
    ],
    # data files containing optionally loaded demonstration data
    'demo': [
        'demo/demo_data.xml',
    ],
}`);

    assert(manifest.name == "A Module");
    assert(manifest.module_version.isStandard == false);
    assert(manifest.module_version.toString == "1.0");
    assert(manifest.module_version.rawVersion == "1.0");
    assert(manifest.dependencies == ["base"]);
}

// Test multithreading
unittest {
    immutable auto test_manifest = `{
        'name': "A Module",
        'version': '%s.0',
        'depends': ['base'],
        'author': "Author Name",
        'category': 'Category',
        'description': """
        Description text
        """,
        # data files always loaded at installation
        'data': [
            'views/mymodule_view.xml',
        ],
        # data files containing optionally loaded demonstration data
        'demo': [
            'demo/demo_data.xml',
        ],
    }`;

    import std.parallelism: taskPool;
    import std.range;
    import std.random;

    // Try to evaluate manifest from different threads
    foreach(i; taskPool.parallel(test_manifest.repeat.take(30), 1)) {
        auto ver = std.random.uniform(2, 1000);
        const auto manifest = parseOdooManifest(i.format(ver));
        assert(manifest.name == "A Module");
        assert(manifest.module_version.isStandard == false);
        assert(manifest.module_version.toString == "%s.0".format(ver));
        assert(manifest.module_version.rawVersion == "%s.0".format(ver));
        assert(manifest.dependencies == ["base"]);
    }
}
