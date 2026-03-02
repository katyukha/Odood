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
