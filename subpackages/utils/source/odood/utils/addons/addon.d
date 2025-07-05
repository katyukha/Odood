module odood.utils.addons.addon;

private import std.typecons: Nullable, nullable, tuple;
private import std.algorithm.searching: startsWith;
private import std.algorithm.comparison: cmp;
private import std.algorithm.sorting: sort;
private import std.exception: enforce;
private import std.conv: to;
private import std.format: format;
private import std.file: SpanMode;
private import std.regex: matchFirst;
private import std.range: empty;

private import thepath: Path;
private import versioned: Version;

private import odood.utils.addons.addon_changelog;
private import odood.utils.addons.addon_manifest;


/** Simple struct to represent single Odoo addon.
  * This struct is not bound to any project,
  * but represents the addon on filesystem, with ability to fetch
  * additional info about this addon by reading manifest
  **/
final class OdooAddon {
    private immutable string _name;
    private immutable Path _path;
    private immutable Path _manifest_path;
    private OdooAddonManifest _manifest;

    @disable this();

    /** Initialize addon from path on filesystem, with automatic
      * computation of name of addon.
      *
      * Params:
      *     path = Path to addon on filesystem
      **/
    this(in Path path) {
        _path = path.toAbsolute;
        _name = _path.baseName;
        _manifest_path = getAddonManifestPath(_path).get;
        _manifest = parseOdooManifest(_manifest_path);
    }

    /// name of the addon
    auto name() const => _name;

    /// path to the addon on filesystem
    auto path() const => _path;

    /// path to addon's manifest
    auto manifest_path() const => _manifest_path;

    /// module manifest
    auto manifest() const => _manifest;

    /// Addons are comparable by name
    pure nothrow int opCmp(in OdooAddon other) const {
        return cmp(_name, other._name);
    }

    /// Check if addons are equal
    pure nothrow bool opEquals(in OdooAddon other) const {
        return opCmp(other) == 0;
    }

    /// Convert addon to string
    override string toString() const {
        return "%s [%s]".format(_name, _path);
    }

    /// Read changelog entries for addon
    auto readChangelogEntries(
            in Nullable!Version start_ver=Nullable!Version.init,
            in Nullable!Version end_ver=Nullable!Version.init) const {
        OdooAddonChangelogEntrie[] result;

        auto changelog_path = _path.join("changelog");
        if (!changelog_path.exists) {
            return result;
        }
        foreach (p; changelog_path.walkBreadth) {
            auto m = matchFirst(
                p.baseName, `^changelog.(\d+\.\d+\.\d+).md$`);
            if (!m.empty) {
                auto entrie = OdooAddonChangelogEntrie(m[1], p.readFileText);
                if (!start_ver.isNull && start_ver.get >= entrie.ver)
                    // Start ver is defined end entrie version is less than start ver, then skip
                    continue;
                if (!end_ver.isNull && end_ver.get < entrie.ver)
                    /// End ver is defined and etrie version is greater than end ver, then skip
                    continue;
                result ~= entrie;
            }
        }
        result.sort!("a > b");  // Sort results
        return result;
    }

    /// Read changelog for addon
    Nullable!string readChangelog(
            in Nullable!Version start_ver=Nullable!Version.init,
            in Nullable!Version end_ver=Nullable!Version.init) {
        auto changelog_entries = readChangelogEntries(
            start_ver: start_ver,
            end_ver: end_ver);
        if (changelog_entries.empty) {
            return Nullable!(string).init;
        }

        string result = "# Changelog\n\n";
        // Note, assume changelog entries already sorted here.
        foreach(entrie; changelog_entries) {
            result ~= "## Version " ~ entrie.ver.toString ~ "\n\n";
            result ~= entrie.data ~ "\n\n";
        }
        return result.nullable;
    }
}

unittest {
    import odood.utils.versioned: Version;
    import odood.utils.odoo.std_version: OdooStdVersion;

    import unit_threaded.assertions;

    auto test_addon_path = Path("test-data", "test_addon");
    auto test_addon = new OdooAddon(test_addon_path);
    test_addon.manifest.module_version.should == OdooStdVersion("18.0.1.2.0");
    test_addon.manifest.name.should == "Test addon";
    test_addon.manifest.dependencies.should == ["base", "web"];

    auto changelog_entries = test_addon.readChangelogEntries;
    changelog_entries.length.should == 3;
    changelog_entries[0].ver.should == Version("1.2.0");
    changelog_entries[0].data.should == "Some version description for version 1.2.0";
    changelog_entries[1].ver.should == Version("1.1.0");
    changelog_entries[1].data.should == "Version 1.1.0";
    changelog_entries[2].ver.should == Version("1.0.0");
    changelog_entries[2].data.should == "Initial release";

    test_addon.readChangelog.get.should == (
        "# Changelog\n\n" ~
        "## Version 1.2.0\n\n" ~
        "Some version description for version 1.2.0\n\n" ~
        "## Version 1.1.0\n\n" ~
        "Version 1.1.0\n\n" ~
        "## Version 1.0.0\n\n" ~
        "Initial release\n\n"
    );

    test_addon.readChangelog(start_ver: Version(1,0).nullable).get.should == (
        "# Changelog\n\n" ~
        "## Version 1.2.0\n\n" ~
        "Some version description for version 1.2.0\n\n" ~
        "## Version 1.1.0\n\n" ~
        "Version 1.1.0\n\n"
    );

    test_addon.readChangelog(start_ver: Version(1,0).nullable, end_ver: Version(1,1).nullable).get.should == (
        "# Changelog\n\n" ~
        "## Version 1.1.0\n\n" ~
        "Version 1.1.0\n\n"
    );
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

///
unittest {
    import unit_threaded.assertions;

    auto test_addon_path = Path("test-data", "test_addon");
    test_addon_path.isOdooAddon.shouldBeTrue();
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


///
unittest {
    import unit_threaded.assertions;

    auto test_addon_path = Path("test-data", "test_addon");
    test_addon_path.getAddonManifestPath.get.should == test_addon_path.join("__manifest__.py");

    Path("test-data").getAddonManifestPath.isNull.shouldBeTrue;
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
