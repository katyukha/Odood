module odood.utils.addons.addon_version;

private import std.string;
private import std.algorithm;
private import std.conv;
private import std.array;
private import std.exception;

private import odood.utils.odoo.serie;
private import odood.exception;


/// This struct represents version of Odoo addon
@safe pure struct OdooAddonVersion {
    private OdooSerie _serie;
    private uint _major;
    private uint _minor;
    private uint _patch;
    private string _raw_version;
    private bool _is_standard;

    @disable this();

    this(in OdooSerie serie, in uint major, in uint minor, in uint patch) pure {
        _serie = serie;
        _major = major;
        _minor = minor;
        _patch = patch;
        _is_standard = true;
        _raw_version = _serie.toString ~ "." ~ _major.to!string ~ "." ~ _minor.to!string ~ "." ~ patch.to!string;
    }

    this(in uint serie_major, in uint serie_minor,  in uint major, in uint minor, in uint patch) pure {
        this(OdooSerie(serie_major, serie_minor), major, minor, patch);
    }

    this(in string addon_version) pure {
        _raw_version = addon_version.idup;

        try {
            uint[] parts = _raw_version.split(".").map!((in p) => p.to!uint).array;
            if (parts.length == 5) {
                _serie = OdooSerie(parts[0], parts[1]);
                _major = parts[2];
                _minor = parts[3];
                _patch = parts[4];
                _is_standard = true;
            } else {
                _is_standard = false;
            }
        } catch (Exception e) {
            _is_standard = false;
        }
    }

    /// Full (unparsed) version of module
    auto rawVersion() const { return _raw_version; }

    /// True if version is valid (X.X.Y.Y.Y format)
    auto isStandard() const { return _is_standard; }

    /// Display version as string
    string toString() const { return _raw_version; }

    /// Odoo Serie extracted from addon's version
    auto serie() const 
    in (isStandard) {
        return _serie;
    }

    /// Major addon version (first number after serie)
    auto major() const
    in (isStandard) {
        return _major;
    }

    /// Minor addon version (second number after serie)
    auto minor() const
    in (isStandard) {
        return _minor;
    }

    /// Patch addon version (third number after serie)
    auto patch() const
    in (isStandard) {
        return _patch;
    }

    // Comparison operators
    int opCmp(in OdooAddonVersion other) const pure nothrow {
        // If both versions are standard, then we have to compare parts
        // of versions.
        if (this.isStandard && other.isStandard) {
            if (this.serie == other.serie) {
                if (this.major == other.major) {
                    if (this.minor == other.minor) {
                        if (this.patch == other.patch)
                            return 0;
                        return this.patch < other.patch ? -1 : 1;
                    }
                    return this.minor < other.minor ? -1 : 1;
                }
                return this.major < other.major ? -1 : 1;
            }
            return this.serie < other.serie ? -1 : 1;
        }

        // Otherwise, we just compare string representations of versions.
        // TODO: Possibly, in future it would be better to split
        // strings on parts and compare parts
        if (this.rawVersion == other.rawVersion)
            return 0;
        return this.rawVersion < other.rawVersion ? -1 : 1;
    }

    bool opEquals(in OdooAddonVersion other) const pure nothrow {
        if (this.isStandard && other.isStandard)
            return this.serie == other.serie &&
                this.major == other.major &&
                this.minor == other.minor &&
                this.patch == other.patch;
        return this.rawVersion == other.rawVersion;
    }

    /** Ensure that addon versions is in standard format
      **/
    auto ref ensureIsStandard() const pure {
        enforce!OdoodException(
            isStandard, "Odoo addon version '%s' does not confirm version standard!".format(rawVersion));
        return this;
    }

    /** Return this version for different Odoo serie
      **/
    auto withSerie(in OdooSerie serie) const pure {
        return OdooAddonVersion(serie, major, minor, patch);
    }

    /// ditto
    auto withSerie(in uint serie_major, in uint serie_minor=0) const pure {
        return OdooAddonVersion(serie_major, serie_minor, major, minor, patch);
    }

    unittest {
        import unit_threaded.assertions;

        auto v = OdooAddonVersion("15.0.1.2.3");
        v.withSerie(16).should == OdooAddonVersion("16.0.1.2.3");
    }

    // TODO: add method to return addon's part of version as semver
    // TODO: add method to increase major, minor, patch
}

@safe unittest {
    import core.exception: AssertError;
    import unit_threaded.assertions;

    auto v = OdooAddonVersion("15.0.1.2.3");
    v.isStandard.shouldBeTrue();
    v.serie.should == OdooSerie(15);
    v.major.should == 1;
    v.minor.should == 2;
    v.patch.should == 3;
    v.toString.should == "15.0.1.2.3";

    v = OdooAddonVersion(OdooSerie(15), 1, 2, 3);
    v.isStandard.shouldBeTrue();
    v.serie.should == OdooSerie(15);
    v.major.should == 1;
    v.minor.should == 2;
    v.patch.should == 3;
    v.toString.should == "15.0.1.2.3";

    v = OdooAddonVersion(15, 0, 1, 2, 3);
    v.isStandard.shouldBeTrue();
    v.serie.should == OdooSerie(15);
    v.major.should == 1;
    v.minor.should == 2;
    v.patch.should == 3;
    v.toString.should == "15.0.1.2.3";

    v = OdooAddonVersion("15.0.1.2");
    v.isStandard.shouldBeFalse();
    v.serie.shouldThrow!AssertError;
    v.major.shouldThrow!AssertError;
    v.minor.shouldThrow!AssertError;
    v.patch.shouldThrow!AssertError;
    v.toString.should == "15.0.1.2";
}


// Test comparison operators
@safe unittest {
    import unit_threaded.assertions;

    alias V = OdooAddonVersion;

    assert(V("15.0.1.2.3") == V(15, 0, 1, 2, 3));
    assert(V("15.0.1.2.3") <= V(15, 0, 1, 2, 3));
    assert(V("15.0.1.2.3") < V(15, 0, 1, 2, 4));
    assert(V("15.0.1.2.3") >= V(15, 0, 1, 2, 3));
    assert(V("15.0.1.2.3") > V(15, 0, 1, 2, 2));

    assert(V("1.2.3") == V("1.2.3"));
    assert(V("1.2.3") <= V("1.2.3"));
    assert(V("1.2.3") < V("1.2.4"));
    assert(V("1.2.3") >= V("1.2.3"));
    assert(V("1.2.3") > V("1.2.2"));
}
