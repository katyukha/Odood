module odood.utils.addons.addon_manifest;

private import std.typecons: Nullable, nullable, tuple;
private import std.conv: to;

private import pyd.embedded: py_eval;
private import pyd.pydobject: PydObject;
private import pyd.make_object: PydConversionException;

private import thepath: Path;

private import odood.utils.addons.addon_version;


/** Struct designed to read addons manifest
  **/
struct OdooAddonManifest {
    private PydObject _manifest;

    this(in Path path) {
        _manifest = py_eval(path.readFileText);
    }

    /// Allows to access manifest as pyd object
    auto raw_manifest() {
        return _manifest;
    }

    /// Is addon installable
    bool installable() {
        return _manifest.get("installable", true).to_d!bool;
    }

    /// Is this addon application
    bool application() {
        return _manifest.get("application", false).to_d!bool;
    }

    /** Price info for this addon
      *
      * Returns:
      *     tuple with following fields:
      *     - currency
      *     - price
      *     - is_set
      **/
    auto price() {
        string currency = _manifest.get("currency","EUR").to_d!string;
        float price;
        if (_manifest.has_key("price")) {
            try
                price = _manifest["price"].to_d!float;
            catch (PydConversionException)
                price = _manifest["price"].to_d!(string).to!float;
            return tuple!(
                "currency", "price", "is_set"
            )(currency, price, true);
        }
        return tuple!(
            "currency", "price", "is_set"
        )(currency, price, false);
    }

    /// Return list of dependencies of addon
    string[] dependencies() {
        if (_manifest.has_key("depends"))
            return _manifest["depends"].to_d!(string[]);
        return [];
    }

    /// Return list of python dependencies
    string[] python_dependencies() {
        if (!_manifest.has_key("external_dependencies"))
            return [];
        if (!_manifest["external_dependencies"].has_key("python"))
            return [];
        return _manifest["external_dependencies"]["python"].to_d!(string[]);
    }

    /// Returns parsed module version
    auto module_version() {
        // If version is not specified, then return "1.0"
        return OdooAddonVersion(_manifest.get("version", "1.0").to_d!string);
    }

    /// Access manifest item as string:
    string opIndex(in string index) {
        return _manifest.get(index, "").to_d!string;
    }

}


// Initialize pyd as early as possible.
shared static this() {
    import pyd.def: py_init;
    py_init();
}
