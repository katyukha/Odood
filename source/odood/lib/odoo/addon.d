module odood.lib.odoo.addon;

private import std.typecons: Nullable, nullable, Tuple;
private import std.algorithm.searching: startsWith;
private import std.exception : enforce;
private import std.conv : to;

private import pyd.embedded: py_eval;
private import pyd.pydobject: PydObject;

private import thepath: Path;


/** Struct designed to read addons manifest
  **/
private struct OdooAddonManifest {
    private PydObject _manifest;

    this(in Path path) {
        _manifest = py_eval(path.readFileText);
    }

    /// Is addon installable
    @property bool installable() {
        return _manifest.get("installable", true).to_d!bool;
    }

    /// Is this addons application
    @property bool application() {
        return _manifest.get("application", false).to_d!bool;
    }

    // TODO: Parse the version to some specific struct, that
    //       have to automatically guess module version in same way as odoo do
    @property string module_version() {
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
    @property auto name() const {
        return _name;
    }

    /// path to the addon on filesystem
    @property auto path() const {
        return _path;
    }

    /// module manifest
    @property auto manifest() {
        if (_manifest.isNull)
            _manifest = OdooAddonManifest(_manifest_path).nullable;

        return _manifest.get;
    }

    /// Get module manifest
    auto getManifest() const {
        return OdooAddonManifest(_manifest_path);
    }
}


/// Check if provided path is odoo module
bool isOdooAddon(in Path path) {
    if (!path.exists)
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
