module odood.utils.addons.addon_changelog;

private import std.string: strip;
private import std.regex: matchFirst;
private import std.typecons: Nullable, nullable;

private import versioned: Version;


/// Filename pattern for a single changelog entry: changelog.X.Y.Z.md
package enum string CHANGELOG_FILE_PATTERN = `^changelog.(\d+\.\d+\.\d+).md$`;


/// This struct represents single changelog entry
struct OdooAddonChangelogEntry {
    private Version _ver;
    private string _data;

    @disable this();

    pure this(string version_raw, string data) {
        this(Version(version_raw), data);
    }

    pure this(Version ver, string data) {
        this._ver = ver;
        this._data = data.strip;
    }

    /// Version of this changelog entry
    auto ver() const => _ver;

    /// Data of changelog entry
    auto data() const => _data;

    int opCmp(in OdooAddonChangelogEntry other) {
        return this._ver.opCmp(other._ver);
    }

    int opEquals(in OdooAddonChangelogEntry other) {
        return this._ver.opEquals(other._ver);
    }
}

///
unittest {
    import unit_threaded.assertions;

    auto e = OdooAddonChangelogEntry("1.2.3", "  Fixed something.  ");
    e.ver.toString.shouldEqual("1.2.3");
    e.data.shouldEqual("Fixed something.");  // strips surrounding whitespace
}

/// Ordering follows semantic version
unittest {
    import unit_threaded.assertions;

    auto a = OdooAddonChangelogEntry("1.0.0", "initial");
    auto b = OdooAddonChangelogEntry("2.0.0", "major");
    auto c = OdooAddonChangelogEntry("1.0.0", "same");

    (a < b).shouldBeTrue;
    (b > a).shouldBeTrue;
    (a == c).shouldBeTrue;
    (a != b).shouldBeTrue;
}


/** Version encoded in a changelog file name, or null when the name is not a
  * changelog entry file (changelog.X.Y.Z.md).
  *
  * The version lives entirely in the name, so callers can range-filter (and
  * thus skip reading) out-of-range files before touching their content.
  **/
Nullable!Version matchChangelogFileVersion(in string filename) {
    auto m = matchFirst(filename, CHANGELOG_FILE_PATTERN);
    if (m.empty)
        return typeof(return).init;
    return Version(m[1]).nullable;
}

///
unittest {
    import unit_threaded.assertions;

    matchChangelogFileVersion("changelog.1.2.0.md").get.should == Version("1.2.0");
    matchChangelogFileVersion("README.md").isNull.shouldBeTrue;
    matchChangelogFileVersion("changelog.bad.md").isNull.shouldBeTrue;
}
