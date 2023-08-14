module odood.utils.addons.addon;

private import std.logger;
private import std.typecons: Nullable, nullable, tuple;
private import std.algorithm.searching: startsWith;
private import std.exception: enforce;
private import std.conv: to;
private import std.file: SpanMode;

private import pyd.embedded: py_eval;
private import pyd.pydobject: PydObject;
private import pyd.make_object: PydConversionException;

private import thepath: Path;


/** Struct designed to read addons manifest
  **/
private struct OdooAddonManifest {
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

    // TODO: Parse the version to some specific struct, that
    //       have to automatically guess module version in same way as odoo do
    string module_version() {
        return _manifest.get("version", "").to_d!string;
    }

    /// Access manifest item as string:
    string opIndex(in string index) {
        return _manifest.get(index, "").to_d!string;
    }

}


/** Simple struct to represent single Odoo addon.
  * This struct is not bound to any project,
  * but represents the addon on filesystem, with ability to fetch
  * additional info about this addon by reading manifest
  **/
final class OdooAddon {
    private immutable string _name;
    private immutable Path _path;
    private immutable Path _manifest_path;
    private Nullable!OdooAddonManifest _manifest;

    @disable this();

    /** Initialize addon from path on filesystem, with automatic
      * computation of name of addon.
      *
      * Params:
      *     path = Path to addon on filesystem
      **/
    this(in Path path) {
        // TODO: there is no need to specify name here. It have to be computed based on path.
        this._path = path.toAbsolute;
        this._name = _path.baseName;
        this._manifest_path = getAddonManifestPath(_path).get;
    }

    /// name of the addon
    auto name() const => _name;

    /// path to the addon on filesystem
    auto path() const => _path;

    /// module manifest
    auto manifest() {
        if (_manifest.isNull)
            _manifest = OdooAddonManifest(_manifest_path).nullable;

        return _manifest.get;
    }

    /// Get module manifest
    auto getManifest() const => OdooAddonManifest(_manifest_path);

    /// Addons are comparable by name
    pure nothrow int opCmp(in OdooAddon other) const {
        import std.algorithm;
        return cmp(_name, other._name);
    }

    ///
    pure nothrow bool opEquals(in OdooAddon other) const {
        return opCmp(other) == 0;
    }
}


/// Check if provided path is odoo module
bool isOdooAddon(in Path path) {
    if (!path.exists)
        return false;

    if (path.exists && path.isSymlink && !path.readLink.exists)
        // Broken symlink, so it is not valid addon
        return false;

    if (!path.isDir)
        return false;

    if (!path.getAddonManifestPath.isNull)
        return true;

    return false;
}


/** Find path to odoo addon manifest.
  * If no manifest found, then result will be null.
  **/
Nullable!Path getAddonManifestPath(in Path path) {
    if (path.join("__manifest__.py").exists)
        return path.join("__manifest__.py").nullable;
    if (path.join("__openerp__.py").exists)
        return path.join("__openerp__.py").nullable;
    return Nullable!Path.init;
}


/** Find odoo addons in specified path.
  *
  * Params:
  *     path = path to addon or directory that contains addons
  *     recursive = if set to true, then search for addons in subdirectories
  *
  * Returns:
  *     Array of OdooAddons found in specified path.
  **/
OdooAddon[] findAddons(in Path path, in bool recursive=false) {
    if (isOdooAddon(path))
        return [new OdooAddon(path)];

    OdooAddon[] res;

    auto walk_mode = recursive ? SpanMode.breadth : SpanMode.shallow;
    foreach(addon_path; path.walk(walk_mode)) {
        if (addon_path.isInside(path.join("setup")))
            // Skip modules defined in OCA setup folder to avoid duplication.
            continue;
        if (addon_path.isOdooAddon)
            res ~= new OdooAddon(addon_path);
    }
    return res;
}
