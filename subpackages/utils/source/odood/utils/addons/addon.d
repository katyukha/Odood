module odood.utils.addons.addon;

private import std.typecons: Nullable, nullable, tuple;
private import std.algorithm.searching: startsWith;
private import std.algorithm.comparison: cmp;
private import std.exception: enforce;
private import std.conv: to;
private import std.file: SpanMode;

private import thepath: Path;

private import odood.utils.addons.addon_manifest;


/** Simple struct to represent single Odoo addon.
  * This struct is not bound to any project,
  * but represents the addon on filesystem, with ability to fetch
  * additional info about this addon by reading manifest
  **/
final class OdooAddon {
    private immutable string _name;
    private immutable Path _path;
    private OdooAddonManifest _manifest;

    @disable this();

    /** Initialize addon from path on filesystem, with automatic
      * computation of name of addon.
      *
      * Params:
      *     path = Path to addon on filesystem
      **/
    this(in Path path) {
        this._path = path.toAbsolute;
        this._name = _path.baseName;
        this._manifest = parseOdooManifest(getAddonManifestPath(_path).get);
    }

    /// name of the addon
    auto name() const => _name;

    /// path to the addon on filesystem
    auto path() const => _path;

    /// module manifest
    auto manifest() const => _manifest;

    /// Addons are comparable by name
    pure nothrow int opCmp(in OdooAddon other) const {
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
  * If provided path is path to addon, then it will be included in result.
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
