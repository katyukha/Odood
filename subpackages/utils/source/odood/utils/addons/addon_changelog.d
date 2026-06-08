module odood.utils.addons.addon_changelog;

private import std.string: strip;

private import versioned: Version;


/// This struct represents single changelog entry
struct OdooAddonChangelogEntry {
    private Version _ver;
    private string _data;

    @disable this();

    pure this(string version_raw, string data) {
        this._ver = Version(version_raw);
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
