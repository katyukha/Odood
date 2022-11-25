/// This module handles Odoo seris (12.0, 13.0, etc)
module odood.lib.odoo_serie;

private import std.array: split;
private import std.conv: to;
private import std.string : format;


struct OdooSerie {
    private uint _major;
    private uint _minor;
    private bool _isValid = false;

    this(in string ver) {
        auto parts = ver.split(".");
        if (parts.length == 2) {
            this._major = parts[0].to!uint;
            this._minor = parts[1].to!uint;
            this._isValid = true;
        } else if (parts.length == 1) {
            this._major = parts[0].to!uint;
            this._minor = 0;
            this._isValid = true;
        }
    }

    string toString() const
    {
        if (this._isValid) {
            return "%s.%s".format(this._major, this._minor);
        }
        return "<invalid odoo serie>";
    }

    @property bool isValid() const { return this._isValid; }
    @property uint major() const { return this._major; }
    @property uint minor() const { return this._minor; }

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
    }

    int opCmp(in OdooSerie other) const
    in
    {
        assert(this.isValid);
        assert(other.isValid);
    }
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

    int opCmp(in string other) const {
        return this.opCmp(OdooSerie(other));
    }

    bool opEquals(in OdooSerie other) const
    in
    {
        assert(this.isValid);
        assert(other.isValid);
    }
    do
    {
        return this.major == other.major && this.minor == other.minor;
    }

    int opEquals(in string other) const {
        return this.opEquals(OdooSerie(other));
    }

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
    }
}

