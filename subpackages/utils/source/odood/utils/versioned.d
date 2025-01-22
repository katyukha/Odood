module odood.utils.versioned;

private import std.conv: to, ConvOverflowException, ConvException;
private import std.range: empty, zip;
private import std.algorithm.searching: canFind;
private import std.string : isNumeric;
private import std.array: split;


enum VersionPart {
    MAJOR,
    MINOR,
    PATCH,
    PRERELEASE,
    BUILD
}


@safe pure struct Version {
    private uint _major=0;
    private uint _minor=0;
    private uint _patch=0;
    private string _prerelease;
    private string _build;
    private bool _isValid=false;

    this(in uint major, in uint minor=0, in uint patch=0) nothrow pure {
        _major = major;
        _minor = minor;
        _patch = patch;
        _isValid = true;
    }

    this(in string v) pure {
        try {
            parseVersionString(v);
            _isValid = true;
        } catch (ConvException) {
            // Cannot convert one of version parts to uint,
            // thus version is not valid
            _isValid = false;
        }
    }

    private void parseVersionString(in string v) pure {
        // TODO: Add validation
        // TODO: Add support of 'v' prefix
        if (v.length == 0) return;

        /* Idea of parsing is simple:
         * start looking for major version part and take all symbols up to
         * delimiter. When delimiter is reached, then save this value
         * as current part, and change the part we are looking for to next one.
         * Each part can have different delimiters. For example, when we are
         * looking for MAJOR, the delimiters are ('.', '-', '+'), but when
         * we are looking for PATCH, the delimiters are ('-', '+'), because
         * we do not expect version parts except prerelease (which separated
         * via '-') and build (which separated via '+').
         */
        uint start = 0;
        VersionPart stage = VersionPart.MAJOR;
        for(uint i=0; i < v.length; i++) {
            if (i < start) continue;
            auto current = v[i];
            final switch(stage) {
                case VersionPart.MAJOR:
                    if (i == v.length -1) {
                        _major = v[start .. $].to!uint;
                    } else if (['.', '-', '+'].canFind(current)) {
                        _major = v[start .. i].to!uint;
                        start = i + 1;
                    }
                    switch(current) {
                        case '.':
                            stage = VersionPart.MINOR;
                            break;
                        case '-':
                            stage = VersionPart.PRERELEASE;
                            break;
                        case '+':
                            stage = VersionPart.BUILD;
                            break;
                        default: continue;
                    }
                    break;
                case VersionPart.MINOR:
                    if (i == v.length - 1) {
                        _minor = v[start .. $].to!uint;
                    } else if (['.', '-', '+'].canFind(current)) {
                        _minor = v[start .. i].to!uint;
                        start = i + 1;
                    }
                    switch(current) {
                        case '.':
                            stage = VersionPart.PATCH;
                            break;
                        case '-':
                            stage = VersionPart.PRERELEASE;
                            break;
                        case '+':
                            stage = VersionPart.BUILD;
                            break;
                        default: continue;
                    }
                    break;
                case VersionPart.PATCH:
                    if (i == v.length - 1) {
                        _patch = v[start .. $].to!uint;
                    } else if (['-', '+'].canFind(current)) {
                        _patch = v[start .. i].to!uint;
                        start = i + 1;
                    }
                    switch(current) {
                        case '-':
                            stage = VersionPart.PRERELEASE;
                            break;
                        case '+':
                            stage = VersionPart.BUILD;
                            break;
                        default: continue;
                    }
                    break;
                case VersionPart.PRERELEASE:
                    if (i == v.length - 1) {
                        _prerelease = v[start .. $];
                    } else if (current == '+') {
                        _prerelease = v[start .. i];
                        i += 1;
                        start = i;
                        stage = VersionPart.BUILD;
                    }
                    break;
                case VersionPart.BUILD:
                    if (i == v.length - 1) {
                        _build = v[start .. $];
                        break;
                    }
                    break;
            }
        }
    }

    nothrow uint major() const pure { return _major; }
    nothrow uint minor() const pure { return _minor; }
    nothrow uint patch() const pure { return _patch; }
    nothrow string prerelease() const pure { return _prerelease; }
    nothrow string build() const pure { return _build; }

    nothrow bool isValid() const pure { return _isValid; }
    nothrow bool isStable() const pure { return _prerelease.empty; }

    nothrow string toString() const pure {
        string result = _major.to!string ~ "." ~ _minor.to!string ~ "." ~
            _patch.to!string;
        if (_prerelease.length > 0)
            result ~= "-" ~ _prerelease;
        if (_build.length > 0)
            result ~= "+" ~ _build;
        return result;
    }

    ///
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").major.should == 1;
        Version("1.2.3").minor.should == 2;
        Version("1.2.3").patch.should == 3;
        Version("1.2.3").toString.should == "1.2.3";
        Version("1.2.3").isValid.should == true;

        Version("1.2").major.should == 1;
        Version("1.2").minor.should == 2;
        Version("1.2").patch.should == 0;
        Version("1.2").toString.should == "1.2.0";
        Version("1.2").isValid.should == true;

        Version("1").major.should == 1;
        Version("1").minor.should == 0;
        Version("1").patch.should == 0;
        Version("1").toString.should == "1.0.0";
        Version("1").isValid.should == true;

        Version("1.2.3-alpha").prerelease.should == "alpha";
        Version("1.2.3-alpha").isValid.should == true;
        Version("1.2.3-alpha+build").prerelease.should == "alpha";
        Version("1.2.3-alpha+build").build.should == "build";
        Version("1.2.3-alpha+build").toString.should == "1.2.3-alpha+build";
        Version("1.2.3-alpha+build").isValid.should == true;

        Version("1.2-alpha+build").major.should == 1;
        Version("1.2-alpha+build").minor.should == 2;
        Version("1.2-alpha+build").patch.should == 0;
        Version("1.2-alpha+build").prerelease.should == "alpha";
        Version("1.2-alpha+build").prerelease.should == "alpha";
        Version("1.2-alpha+build").build.should == "build";
        Version("1.2-alpha+build").toString.should == "1.2.0-alpha+build";
        Version("1.2-alpha+build").isValid.should == true;

        Version("1-alpha+build").major.should == 1;
        Version("1-alpha+build").minor.should == 0;
        Version("1-alpha+build").patch.should == 0;
        Version("1-alpha+build").prerelease.should == "alpha";
        Version("1-alpha+build").prerelease.should == "alpha";
        Version("1-alpha+build").build.should == "build";
        Version("1-alpha+build").toString.should == "1.0.0-alpha+build";
        Version("1-alpha+build").isValid.should == true;

        Version("1.2+build").major.should == 1;
        Version("1.2+build").minor.should == 2;
        Version("1.2+build").patch.should == 0;
        Version("1.2+build").prerelease.should == "";
        Version("1.2+build").prerelease.should == "";
        Version("1.2+build").build.should == "build";
        Version("1.2+build").toString.should == "1.2.0+build";
        Version("1.2+build").isValid.should == true;

        Version("1+build").major.should == 1;
        Version("1+build").minor.should == 0;
        Version("1+build").patch.should == 0;
        Version("1+build").prerelease.should == "";
        Version("1+build").prerelease.should == "";
        Version("1+build").build.should == "build";
        Version("1+build").toString.should == "1.0.0+build";
        Version("1+build").isValid.should == true;

        Version("12.34.56").major.should == 12;
        Version("12.34.56").minor.should == 34;
        Version("12.34.56").patch.should == 56;
        Version("12.34.56").isValid.should == true;
        Version("12.34.56-alpha.beta").prerelease.should == "alpha.beta";
        Version("12.34.56-alpha.beta").isValid.should == true;
        Version("12.34.56-alpha.beta+build").prerelease.should == "alpha.beta";
        Version("12.34.56-alpha.beta+build").build.should == "build";
        Version("12.34.56-alpha.beta+build").toString.should == "12.34.56-alpha.beta+build";
        Version("12.34.56-alpha.beta+build").isValid.should == true;

        Version("12.34.56-alpha").prerelease.should == "alpha";
        Version("12.34.56-alpha-42").prerelease.should == "alpha-42";
        Version("12.34.56-alpha-42").isValid.should == true;

        Version("12.34.56+build").prerelease.should == "";
        Version("12.34.56+build").build.should == "build";
        Version("12.34.56+build-42").build.should == "build-42";
        Version("12.34.56+build-42").isValid.should == true;
    }

    // Test invalid versions
    unittest {
        import unit_threaded.assertions;
        Version("2s").isValid.should == false;
        Version("2.3s").isValid.should == false;
        Version("2.3.4s").isValid.should == false;
        Version("2.3.4-s").isValid.should == true;
    }

    int opCmp(in Version other) const pure {
        // TODO: make it nothrow
        if (this.major != other.major)
            return this.major < other.major ? -1 : 1;
        if (this.minor != other.minor)
            return this.minor < other.minor ? -1 : 1;
        if (this.patch != other.patch)
            return this.patch < other.patch ? -1 : 1;

        // Just copypaste from semver lib
        int compareSufix(scope const string[] suffix, const string[] anotherSuffix)
        {
            if (!suffix.empty && anotherSuffix.empty)
                return -1;
            if (suffix.empty && !anotherSuffix.empty)
                return 1;

            foreach (a, b; zip(suffix, anotherSuffix))
            {
                if (a.isNumeric && b.isNumeric)
                {
                    // to convert parts to integers and comare as integers
                    try {
                        uint ai = a.to!uint,
                             bi = b.to!uint;
                        if (ai != bi)
                            return ai < bi ? -1 : 1;
                        else
                            continue;
                    } catch (ConvOverflowException e) {
                        // Do nothing, this case will be handled later
                    }
                }
                if (a != b)
                    return a < b ? -1 : 1;
            }
            if (suffix.length != anotherSuffix.length)
                return suffix.length < anotherSuffix.length ? -1 : 1;
            else
                return 0;
        }

        // Compare prerelease section of version
        auto result = compareSufix(this.prerelease.split("."), other.prerelease.split("."));
        if (result == 0)
            result = compareSufix(this.build.split("."), other.build.split("."));
        return result;
    }

    /// ditto
    int opCmp(in string other) const pure {
        return this.opCmp(Version(other));
    }

    /// Test version comparisons
    unittest {
        import unit_threaded.assertions;
        assert(Version("1.0.0-alpha") < Version("1.0.0-alpha.1"));
        assert(Version("1.0.0-alpha.1") < Version("1.0.0-alpha.beta"));
        assert(Version("1.0.0-alpha.beta") < Version("1.0.0-beta"));
        assert(Version("1.0.0-beta") < Version("1.0.0-beta.2"));
        assert(Version("1.0.0-beta.2") < Version("1.0.0-beta.11"));
        assert(Version("1.0.0-beta.11") < Version("1.0.0-rc.1"));
        assert(Version("1.0.0-rc.1") < Version("1.0.0"));
        assert(Version("1.0.0-rc.1") > Version("1.0.0-rc.1+build.5"));
        assert(Version("1.0.0-rc.1+build.5") == Version("1.0.0-rc.1+build.5"));
        assert(Version("1.0.0-rc.1+build.5") != Version("1.0.0-rc.1+build.6"));
        assert(Version("1.0.0-rc.2+build.5") != Version("1.0.0-rc.1+build.5"));
    }

    /// Test comparisons with strings
    unittest {
        import unit_threaded.assertions;
        assert(Version("1.0.0-alpha") < "1.0.0-alpha.1");
        assert(Version("1.0.0-alpha.1") < "1.0.0-alpha.beta");
        assert(Version("1.0.0-alpha.beta") < "1.0.0-beta");
        assert(Version("1.0.0-beta") < "1.0.0-beta.2");
        assert(Version("1.0.0-beta.2") < "1.0.0-beta.11");
        assert(Version("1.0.0-beta.11") < "1.0.0-rc.1");
        assert(Version("1.0.0-rc.1") < "1.0.0");
        assert(Version("1.0.0-rc.1") > "1.0.0-rc.1+build.5");
        assert(Version("1.0.0-rc.1+build.5") == "1.0.0-rc.1+build.5");
        assert(Version("1.0.0-rc.1+build.5") != "1.0.0-rc.1+build.6");
        assert(Version("1.0.0-rc.2+build.5") != "1.0.0-rc.1+build.5");
    }

    bool opEquals(in Version other) const nothrow pure {
        return this.major == other.major &&
            this.minor == other.minor &&
            this.patch == other.patch &&
            this.prerelease == other.prerelease &&
            this.build == other.build;
    }

    /// ditto
    bool opEquals(in string other) const pure {
        return this.opEquals(Version(other));
    }

    /// Test equality checks
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").should == Version(1, 2, 3);
        Version("1.2").should == Version(1, 2);
        Version("1.0.3").should == Version(1, 0, 3);
        // TODO: more tests needed
    }

    /// Test equality checks with strings
    unittest {
        import unit_threaded.assertions;
        assert(Version("1.2.3") == "1.2.3");
        assert(Version("1.2") == "1.2");
        assert(Version("1.0.3") == "1.0.3");
        // TODO: more tests needed
    }

    /// Return new version with increased major part
    auto incMajor() const pure {
        return Version(major +1 , 0, 0);
    }

    /// Test increase of major version
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").incMajor.should == Version("2.0.0");
    }

    /// Return new version with increased minor part
    auto incMinor() const pure {
        return Version(major, minor + 1, 0);
    }

    /// Test increase of minor version
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").incMinor.should == Version("1.3.0");
    }

    /// Return new version with increased patch part
    auto incPatch() const pure {
        return Version(major, minor, patch + 1);
    }

    /// Test increase of minor version
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").incPatch.should == Version("1.2.4");
    }

    /// Determine if version differs on major, minor or patch level
    VersionPart differAt(in Version other) const pure
    in (this != other && this.isValid && other.isValid) {
        if (this.major != other.major) return VersionPart.MAJOR;
        if (this.minor != other.minor) return VersionPart.MINOR;
        if (this.patch != other.patch) return VersionPart.PATCH;
        if (this.prerelease != other.prerelease) return VersionPart.PRERELEASE;
        if (this.build != other.build) return VersionPart.BUILD;
        assert(0, "differAt cannot compare equal versions.");
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
