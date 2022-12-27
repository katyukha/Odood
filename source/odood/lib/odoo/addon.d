module odood.lib.odoo.addon;

private import std.typecons: Nullable, nullable, Tuple;
private import std.algorithm.searching: startsWith;
private import std.exception : enforce;
private import std.conv : to;

private import pyd.embedded: py_eval;

private import thepath: Path;


// This struct represents basic, minimal info about addon
struct OdooAddon {
    string name;
    Path path;

    @disable this();

    this(in Path path, in string name) {
        this.name = name;
        this.path = path;
    }

    this(in Path path) {
        this(path, getAddonName(path));
    }

    auto readManifest() const {
        auto manifest_path = getAddonManifestPath(path).get;
        return py_eval(manifest_path.readFileText);
    }
}


/// Check if provided path is odoo module
bool isOdooAddon(in Path path) {
    if (!path.isDir)
        return false;
    if (!path.exists)
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


/** Find addons inside specified path
  **/
OdooAddon[] findAddons(in Path path) {
    if (isOdooAddon(path)) {
        return [OdooAddon(path)];
    }

    OdooAddon[] res;

    // TODO: update to path.walkBreadth when new version of the path released
    foreach(addon_path; path.walkBreadth) {
        if (addon_path.isInside(path.join("setup")))
            // Skip modules defined in OCA setup folder to avoid duplication.
            continue;
        if (addon_path.isOdooAddon)
            res ~= OdooAddon(addon_path);
    }
    return res;
}
