module odood.utils.odoo;

private import std.string: chomp;
public import odood.utils.odoo.serie: OdooSerie;


/** version in manifest is server version. Thus we have to parse it,
  * because it could contain (for example) enterprise indicator.
  * Thus here we remove version prefix, and return valid server serie.
  **/
OdooSerie parseServerSerie(in string server_version) {
    return OdooSerie(server_version.chomp("+e"));
}

unittest {
    import unit_threaded.assertions;

    parseServerSerie("18.0").should == OdooSerie(18);
    parseServerSerie("18.0").isValid.shouldBeTrue();

    parseServerSerie("18").should == OdooSerie(18);
    parseServerSerie("18").isValid.shouldBeTrue();

    parseServerSerie("18.0+e").should == OdooSerie(18);
    parseServerSerie("18.0+e").isValid.shouldBeTrue();

    parseServerSerie("18+e").should == OdooSerie(18);
    parseServerSerie("18+e").isValid.shouldBeTrue();

    parseServerSerie("18-e").isValid.shouldBeFalse();

    parseServerSerie("18.0-e").isValid.shouldBeFalse();
}
