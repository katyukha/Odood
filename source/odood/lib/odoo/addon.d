module odood.lib.odoo.addon;

private import std.typecons: Nullable, nullable, Tuple;
private import std.algorithm.searching: startsWith;
private import std.exception : enforce;
private import std.conv : to;

private import pyd.embedded: py_eval;

private import thepath: Path;


/** Simple struct to represent single Odoo addons.
  * This struct is not bound to any project config,
  * but represents the addon on filesystem, with ability to fetch
  * additional info about this addon by reading manifest
  **/
struct OdooAddon {
    private string _name;
    private Path _path;

    @disable this();

    /// Initialize addon based on path and name
    this(in Path path, in string name) {
        this._name = name;
        this._path = path;
    }

    /** Initialize addon from path on filesystem, with automatic
      * computation of name of addon.
      **/
    this(in Path path) {
        this(path, getAddonName(path));
    }

    /// name of the addon
    @property name() const {
        return _name;
    }

    /// path to the addon on filesystem
    @property path() const {
        return _path;
    }

    @property installable() {
        // TODO: Cache processed manifest in addon.
        auto manifest = readManifest();
        if (manifest.has_key("installable"))
            return manifest["installable"].to_d!bool;

        // All addons are installable by default
        return true;
    }

    /// Read the module manifest and return it as py_evan result
    auto readManifest() const {
        auto manifest_path = getAddonManifestPath(path).get;
        return py_eval(manifest_path.readFileText);
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


/** Get name of addon based on path to addon
  **/
string getAddonName(in Path path) {
    return path.baseName;
}
