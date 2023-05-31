module odood.lib.addons.addon;

private import std.typecons: Nullable, nullable, tuple;
private import std.algorithm.searching: startsWith;
private import std.exception : enforce;
private import std.conv : to;

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


    // TODO: Parse the version to some specific struct, that
    //       have to automatically guess module version in same way as odoo do
    string module_version() {
        return _manifest.get("version", "").to_d!string;
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

    /// Initialize addon based on path and name
    this(in Path path, in string name) {
        this._name = name;
        this._path = path.toAbsolute;
        this._manifest_path = getAddonManifestPath(_path).get;
    }

    /** Initialize addon from path on filesystem, with automatic
      * computation of name of addon.
      **/
    this(in Path path) {
        this(path, path.baseName);
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
