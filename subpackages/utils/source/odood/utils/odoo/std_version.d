module odood.utils.odoo.std_version;

private import std.format: format;
private import std.algorithm.iteration: map, splitter, filter;
private import std.conv: to;
private import std.array: array, join, empty;
private import std.exception: enforce;
private import std.regex;

private import versioned: Version, VersionPart;

private import odood.utils.odoo.serie: OdooSerie;
private import odood.exception;


/** This struct represents standard odoo version.
  * It is used as standard version format in Odoo addons
  * and in some other places.
  * The format is 5 digits: 2 for serie and 3 for version
  **/
@safe pure struct OdooStdVersion {
    private OdooSerie _serie;
    private Version _version;
    private string _raw_version;
    private bool _is_standard = false;

    @disable this();

    this(in OdooSerie serie, in Version v) pure {
        _serie = serie;
        _version = v;
        _is_standard = _serie.isValid && _version.isValid;
        _raw_version = _serie.toString ~ "." ~ _version.toString;
    }

    this(in OdooSerie serie, in uint major, in uint minor, in uint patch) pure {
        this(serie, Version(major, minor, patch));
    }

    this(in uint serie_major, in uint serie_minor,  in uint major, in uint minor, in uint patch) pure {
        this(OdooSerie(serie_major, serie_minor), major, minor, patch);
    }

    this(in uint serie_major, in uint serie_minor,  in Version v) pure {
        this(OdooSerie(serie_major, serie_minor), v);
    }

    this(in string addon_version) pure {
        _raw_version = addon_version.idup;

        /* Here we check 2 things:
         * - find position where to split version on serie and version
         * - count number of dots, that have to be at least 4 (5 number version)
         * Then, all next version parsion we delegate to OdooSerie and Version.
         */
        int split_pos = 0;
        int dots_count = 0;
        for(int i; i < addon_version.length; i++) {
            if (addon_version[i] == '.') {
                dots_count += 1;
                if (dots_count == 2)
                    split_pos = i;
            }
        }
        if (split_pos > 0 && dots_count >= 4) {
            _serie = OdooSerie(addon_version[0 .. split_pos]);
            _version = Version(addon_version[split_pos + 1 .. $]);
            _is_standard = _serie.isValid && _version.isValid;
        } else {
            _is_standard = false;
        }
    }

    /// Full (unparsed) version of module
    auto rawVersion() const { return _raw_version; }

    /// True if version is valid (X.X.Y.Y.Y format)
    auto isStandard() const { return _is_standard; }

    /// True if version is valid (X.X.Y.Y.Y format)
    deprecated("Use .isStandard instead") alias isValid = isStandard;

    /// Display version as string
    string toString() const { return _raw_version; }

    /// Odoo Serie extracted from addon's version
    auto serie() const 
    in (isStandard) {
        return _serie;
    }

    /// semver part of version
    auto semver() const
    in (isStandard) {
        return _version;
    }

    /// Odoo Serie major part of the version
    deprecated("Use .serie.major instead") auto serie_major() const
    in (isStandard) {
        return serie.major;
    }

    /// Odoo Serie major part of the version
    deprecated("Use .serie.minor instead") auto serie_minor() const
    in (isStandard) {
        return serie.minor;
    }

    /// Major addon version (first number after serie)
    auto major() const
    in (isStandard) {
        return _version.major;
    }

    /// Minor addon version (second number after serie)
    auto minor() const
    in (isStandard) {
        return _version.minor;
    }

    /// Patch addon version (third number after serie)
    auto patch() const
    in (isStandard) {
        return _version.patch;
    }

    /// Suffix addon version (everything after third number after serie)
    deprecated("Just combination of 'semver.prerelease + semver.build'")
    auto suffix() const
    in (isStandard) {
        string res = "";
        if (_version.prerelease.length)
            res = _version.prerelease;
        if (_version.build.length) {
            if (res.length) {
                res ~= "+" ~ _version.build;
            } else {
                res = _version.build;
            }
        }
        return res;
    }

    // Comparison operators
    int opCmp(in OdooStdVersion other) const pure {
        // If both versions are standard, then we have to compare parts
        // of versions.
        if (this.isStandard && other.isStandard) {
            if (this._serie == other._serie) {
                if (this._version == other._version)
                    return 0;
                return this._version < other._version ? -1 : 1;
            }
            return this._serie < other._serie ? -1 : 1;
        }

        // Otherwise, we just compare string representations of versions.
        // TODO: Possibly, in future it would be better to split
        // strings on parts and compare parts
        if (this.rawVersion == other.rawVersion)
            return 0;
        return this.rawVersion < other.rawVersion ? -1 : 1;
    }

    bool opEquals(in OdooStdVersion other) const pure {
        if (this.isStandard && other.isStandard)
            return this._serie == other._serie && this._version == other._version;
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
        return OdooStdVersion(serie, _version);
    }

    /// ditto
    auto withSerie(in uint serie_major, in uint serie_minor=0) const pure {
        return OdooStdVersion(serie_major, serie_minor, _version);
    }

    unittest {
        import unit_threaded.assertions;

        auto v = OdooStdVersion("15.0.1.2.3");
        v.withSerie(16).should == OdooStdVersion("16.0.1.2.3");
    }

    // Increment version
    auto incVersion(in VersionPart part) const pure {
        final switch(part) {
            case VersionPart.MAJOR:
                return OdooStdVersion(_serie, _version.incMajor);
            case VersionPart.MINOR:
                return OdooStdVersion(_serie, _version.incMinor);
            case VersionPart.PATCH:
                return OdooStdVersion(_serie, _version.incPatch);
            case VersionPart.PRERELEASE, VersionPart.BUILD:
                throw new OdoodException("Increment of prerelease and build versions not supported yet!");
        }
    }

    /// Return new version with increased major part
    auto incMajor() const pure {
        return incVersion(VersionPart.MAJOR);
    }

    /// Test increase of major version
    unittest {
        import unit_threaded.assertions;
        OdooStdVersion("18.0.1.2.3").incMajor.should == OdooStdVersion("18.0.2.0.0");
    }

    /// Return new version with increased minor part
    auto incMinor() const pure {
        return incVersion(VersionPart.MINOR);
    }

    /// Test increase of minor version
    unittest {
        import unit_threaded.assertions;
        OdooStdVersion("18.0.1.2.3").incMinor.should == OdooStdVersion("18.0.1.3.0");
    }

    /// Return new version with increased patch part
    auto incPatch() const pure {
        return incVersion(VersionPart.PATCH);
    }

    /// Test increase of minor version
    unittest {
        import unit_threaded.assertions;
        OdooStdVersion("18.0.1.2.3").incPatch.should == OdooStdVersion("18.0.1.2.4");
    }

    /// Determine if version differs on major, minor or patch level
    VersionPart differAt(in OdooStdVersion other) const pure
    in (this != other && this.isStandard && other.isStandard && this.serie == other.serie) {
        return this._version.differAt(other._version);
    }

    /// Test differAt
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").differAt(Version(2,3,4)).should == VersionPart.MAJOR;
        Version("1.2.3").differAt(Version(2,2,3)).should == VersionPart.MAJOR;

        Version("1.2.3").differAt(Version(1,3,4)).should == VersionPart.MINOR;
        Version("1.2.3").differAt(Version(1,3,3)).should == VersionPart.MINOR;

        Version("1.2.3").differAt(Version(1,2,4)).should == VersionPart.PATCH;
    }
}

deprecated("Use OdooStdVersion instead.") alias OdooAddonVersion = OdooStdVersion;

@safe unittest {
    import core.exception: AssertError;
    import unit_threaded.assertions;

    auto v = OdooStdVersion("15.0.1.2.3");
    v.isStandard.shouldBeTrue();
    v.serie.should == OdooSerie(15);
    v.major.should == 1;
    v.minor.should == 2;
    v.patch.should == 3;
    v.toString.should == "15.0.1.2.3";

    v = OdooStdVersion(OdooSerie(15), 1, 2, 3);
    v.isStandard.shouldBeTrue();
    v.serie.should == OdooSerie(15);
    v.major.should == 1;
    v.minor.should == 2;
    v.patch.should == 3;
    v.toString.should == "15.0.1.2.3";

    v = OdooStdVersion(15, 0, 1, 2, 3);
    v.isStandard.shouldBeTrue();
    v.serie.should == OdooSerie(15);
    v.major.should == 1;
    v.minor.should == 2;
    v.patch.should == 3;
    v.toString.should == "15.0.1.2.3";

    v = OdooStdVersion("15.0.1.2");
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

    alias V = OdooStdVersion;

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

// Tests from OdooPackager to be compatible with RepoVersion
@safe unittest {
    import unit_threaded.assertions;

    auto v = OdooStdVersion("14.0.1.2.3");
    v.isStandard.shouldBeTrue;
    v.toString().should == "14.0.1.2.3";
    v.serie.major.should == 14;
    v.serie.minor.should == 0;
    v.major.should == 1;
    v.minor.should == 2;
    v.patch.should == 3;
    v.suffix.empty.shouldBeTrue;

    auto v2 = OdooStdVersion("14.0.1.2.3-hotfix-1");
    v2.isStandard.shouldBeTrue;
    v2.toString().should == "14.0.1.2.3-hotfix-1";
    v2.serie.major.should == 14;
    v2.serie.minor.should == 0;
    v2.major.should == 1;
    v2.minor.should == 2;
    v2.patch.should == 3;
    v2.suffix.should == "hotfix-1";

    // Not in semver standard thus not supported by Versioned
    //auto v3 = OdooStdVersion("14.0.1.2.3.hotfix-1");
    //v3.isStandard.shouldBeTrue;
    //v3.toString().should == "14.0.1.2.3-hotfix-1";
    //v3.serie.major.should == 14;
    //v3.serie.minor.should == 0;
    //v3.major.should == 1;
    //v3.minor.should == 2;
    //v3.patch.should == 3;
    //v3.suffix.should == "hotfix-1";

    // Not in semver standard thus not supported by Versioned
    //auto v4 = OdooStdVersion("14.0.1.2.3_hotfix-1");
    //v4.isStandard.shouldBeTrue;
    //v4.toString().should == "14.0.1.2.3-hotfix-1";
    //v4.serie.major.should == 14;
    //v4.serie.minor.should == 0;
    //v4.major.should == 1;
    //v4.minor.should == 2;
    //v4.patch.should == 3;
    //v4.suffix.should == "hotfix-1";

    auto v5 = OdooStdVersion("14.0.1.2.3+hotfix-1");
    v5.isStandard.shouldBeTrue;
    v5.toString().should == "14.0.1.2.3+hotfix-1";
    v5.serie.major.should == 14;
    v5.serie.minor.should == 0;
    v5.major.should == 1;
    v5.minor.should == 2;
    v5.patch.should == 3;
    v5.suffix.should == "hotfix-1";
}

