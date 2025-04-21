/// This module handles Odoo seris (12.0, 13.0, etc)
module odood.utils.odoo.serie;

private import std.array: split;
private import std.conv: to;


/** This struct represetns Odoo serie, and provides convenient
  * mechanics to parse and compare Odoo series
  **/
@safe struct OdooSerie {
    private uint _major;
    private uint _minor;
    private bool _isValid = false;

    /** Construct new Odoo serie instance
      *
      * Params:
      *     ver = string representation of version
      **/
    pure nothrow this(in string ver) {
        auto parts = ver.split(".");
        if (parts.length == 2)
            try {
                _major = parts[0].to!uint;
                _minor = parts[1].to!uint;
            } catch (Exception e) {
                _major = 0;
                _minor = 0;
            }
        else if (parts.length == 1)
            try {
                _major = parts[0].to!uint;
            } catch (Exception e) {
                _major = 0;
                _minor = 0;
            }
        else {
            _major = 0;
            _minor = 0;
        }

        _isValid = (_major > 0) ? true : false;
    }

    /** Construct new Odoo serie instance
      *
      * Params:
      *     major = "major" parto of odoo serie
      *     minor = "minor" part of odoo serie
      **/
    pure nothrow this(in uint major, in uint minor=0) {
        this._major = major;
        this._minor = minor;
        if (_major > 0) _isValid = true;
        else _isValid = false;
    }

    /** Return string representation of Odoo Serie
      **/
    pure nothrow string toString() const {
        if (this._isValid)
            return this._major.to!string ~ "." ~ this._minor.to!string;
        return "<invalid odoo serie>";
    }

    /// Check if odoo serie is valid
    pure nothrow bool isValid() const { return this._isValid; }

    /// Return "major" part of Odoo serie
    pure nothrow uint major() const { return this._major; }

    /// Return "minor" part of Odoo serie
    pure nothrow uint minor() const { return this._minor; }

    ///
    unittest {
        auto s = OdooSerie("12.0");
        assert(s.major == 12);
        assert(s.minor == 0);
        assert(s.isValid);
        assert(s.toString() == "12.0");

        auto s2 = OdooSerie("12");
        assert(s2.major == 12);
        assert(s2.minor == 0);
        assert(s2.isValid);
        assert(s2.toString() == "12.0");

        auto s3 = OdooSerie("12.1.3");
        assert(s3.major == 0);
        assert(s3.minor == 0);
        assert(!s3.isValid);
        assert(s3.toString() == "<invalid odoo serie>");

        auto s4 = OdooSerie("");
        assert(s4.major == 0);
        assert(s4.minor == 0);
        assert(!s4.isValid);
        assert(s4.toString() == "<invalid odoo serie>");

        // Odoo serie must not include enterprise modifier.
        s4 = OdooSerie("18.04+e");
        assert(s4.major == 0);
        assert(s4.minor == 0);
        assert(!s4.isValid);
        assert(s4.toString() == "<invalid odoo serie>");
    }

    pure nothrow int opCmp(in OdooSerie other) const
    in (this.isValid && other.isValid, "Only valid OdooSerie instances are comparable")
    do
    {
        if (this.major == other.major) {
            if (this.minor == other.minor) {
                return 0;
            }
            return this.minor < other.minor ? -1 : 1;
        }
        return this.major < other.major ? -1 : 1;
    }

    pure int opCmp(in string other) const {
        return this.opCmp(OdooSerie(other));
    }

    pure int opCmp(in uint other) const {
        return this.opCmp(OdooSerie(other));
    }

    pure nothrow bool opEquals(in OdooSerie other) const
    in (this.isValid && other.isValid, "Only valid OdooSerie instances are comparable")
    do
    {
        return this.major == other.major && this.minor == other.minor;
    }

    pure int opEquals(in string other) const {
        return this.opEquals(OdooSerie(other));
    }

    pure int opEquals(in uint other) const {
        return this.opEquals(OdooSerie(other));
    }

    ///
    unittest {
        assert(OdooSerie("12.0") < OdooSerie("13.0"));
        assert(OdooSerie("12.0") == OdooSerie("12.0"));
        assert(OdooSerie("12.0") == OdooSerie("12"));
        assert(OdooSerie("12.1") > OdooSerie("12.0"));
        assert(OdooSerie("12.1") != OdooSerie("12.0"));
        assert(OdooSerie("12.0") != OdooSerie("13.0"));

        assert(OdooSerie("12.0") < "13.0");
        assert(OdooSerie("12.0") == "12.0");
        assert(OdooSerie("12.0") == "12");
        assert(OdooSerie("12.1") > "12.0");
        assert(OdooSerie("12.1") != "12.0");
        assert(OdooSerie("12.0") != "13.0");

        assert("12.0" < OdooSerie("13.0"));
        assert("12.0" == OdooSerie("12.0"));
        assert("12.0" == OdooSerie("12"));
        assert("12.1" > OdooSerie("12.0"));
        assert("12.1" != OdooSerie("12.0"));
        assert("12.0" != OdooSerie("13.0"));

        assert(OdooSerie("12.0") < 13);
        assert(OdooSerie("12.0") == 12);
        assert(OdooSerie("12.1") > 12);
        assert(OdooSerie("12.1") != 12);
        assert(OdooSerie("12.0") != 13);

        assert(13 > OdooSerie("12.0"));
        assert(12 == OdooSerie("12.0"));
        assert(12 < OdooSerie("12.1"));
        assert(12 != OdooSerie("12.1"));
        assert(13 != OdooSerie("12.0"));
    }

    /** Compute hash of the OdooSerie to be able to use it as key
      * in asociative arrays.
      **/
    nothrow size_t toHash() const {
        /* Compute hash in similar way as it is done for tuples.
         *
         * See:
         * - https://www.boost.org/doc/libs/1_55_0/doc/html/hash/reference.html#boost.hash_combine
         * - https://github.com/dlang/phobos/blob/10601cc04641b4764ba8ef8b47c3819f7b2e3f1c/std/typecons.d#L1256
         */
        immutable size_t hash_maj = .hashOf(_major);
        immutable size_t hash_min = .hashOf(_minor);

        size_t result = 0;
        result ^= hash_maj + 0x9e3779b9 + (result << 6) + (result >>> 2);
        result ^= hash_min + 0x9e3779b9 + (result << 6) + (result >>> 2);
        return result;
    }

    unittest {
        string[OdooSerie] aa = [
            OdooSerie(12): "1",
            OdooSerie(13): "2",
            OdooSerie(12, 1): "3",
        ];
        assert(aa[OdooSerie("12")] == "1");
        assert(aa[OdooSerie("13")] == "2");
        assert(aa[OdooSerie("12.1")] == "3");
        assert(aa[OdooSerie("12.0")] == "1");
        assert(aa[OdooSerie("13.0")] == "2");

        assert(OdooSerie("12.0").toHash == OdooSerie(12).toHash);
        assert(OdooSerie("12.1").toHash != OdooSerie(12).toHash);
        assert(OdooSerie("12.0").toHash != OdooSerie(13).toHash);
        assert(OdooSerie("12.0").toHash != OdooSerie(12, 1).toHash);
    }
}

