module odood.utils.addons.addon_changelog;

private import std.string: strip;

private import odood.utils.versioned: Version;


/// This struct represents single changelog entries
struct OdooAddonChangelogEntrie {
    private Version _ver;
    private string _data;

    @disable this();

    pure this(string version_raw, string data) {
        this._ver = Version(version_raw);
        this._data = data.strip;
    }

    /// Version of this changelog entrie
    auto ver() const => _ver;

    /// Data of changelog entrie
    auto data() const => _data;

    int opCmp(in OdooAddonChangelogEntrie other) {
        return this._ver.opCmp(other._ver);
    }

    int opEquals(in OdooAddonChangelogEntrie other) {
        return this._ver.opEquals(other._ver);
    }
}
