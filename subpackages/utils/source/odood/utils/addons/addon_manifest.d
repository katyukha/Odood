module odood.utils.addons.addon_manifest;

private import std.format;
private import std.string;
private import std.typecons;

private import thepath;

private import odood.utils.tipy;
private import odood.utils.tipy.python;

private import odood.utils.addons.addon_version;


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
    OdooAddonVersion module_version = OdooAddonVersion("1.0");
    string author;
    string category;
    string description;
    string license;
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

    auto gstate = PyGILState_Ensure();
    scope(exit) PyGILState_Release(gstate);

    auto parsed = callPyFunc(_fn_literal_eval, manifest_content);
    scope(exit) Py_DecRef(parsed);

    // PyDict_GetItemString returns borrowed reference,
    // thus there is no need to call Py_DecRef from our side
    if (auto val = PyDict_GetItemString(parsed, "name".toStringz))
        manifest.name = val.convertPyToD!string;
    if (auto val = PyDict_GetItemString(parsed, "version".toStringz))
        manifest.module_version = OdooAddonVersion(val.convertPyToD!string);
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
private PyObject* _fn_literal_eval;

// Initialize python interpreter (import ast.literal_eval)
shared static this() {
    loadPyLib;

    Py_Initialize();

    auto gstate = PyGILState_Ensure();
    scope(exit) PyGILState_Release(gstate);

    auto mod_ast = PyImport_ImportModule("ast");
    scope(exit) Py_DecRef(mod_ast);

    // Save function literal_eval from ast on module level
    _fn_literal_eval = PyObject_GetAttrString(
        mod_ast, "literal_eval".toStringz
    ).pyEnforce;


}

// Finalize python interpreter (do clean up)
shared static ~this() {
    if (_fn_literal_eval) Py_DecRef(_fn_literal_eval);
    Py_Finalize();
}


// Tests
unittest {
    auto manifest = parseOdooManifest(`{
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
