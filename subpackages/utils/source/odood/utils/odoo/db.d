module odood.utils.odoo.db;

private import std.logger;
private import std.string: toStringz, fromStringz, strip;
private import std.format: format;
private import std.exception: enforce;
private import std.json;

private import deimos.zip;

private import thepath: Path;

private import odood.exception: OdoodException;
private import odood.utils.zip;
private import odood.utils.odoo.serie: OdooSerie;


/** Parse database backup's manifest
  *
  * Params:
  *     path = path to database backup to parse
  *
  * Returns: JSONValue that contains parsed database backup manifest
  **/
auto parseDatabaseBackupManifest(in Path path) {
    int error_code;
    auto zip_obj = zip_open(path.toStringz, ZIP_RDONLY, &error_code);
    scope(exit) zip_close(zip_obj);

    enforce!OdoodException(
        !error_code,
        "Cannot open zip archive %s for reading: %s".format(
            path, format_zip_error(error_code)));

    enforce!OdoodException(
        zip_name_locate(zip_obj, "manifest.json".toStringz, ZIP_FL_ENC_GUESS),
        "Cannot locate 'manifest.json' inside database backup!");

    auto manifest_file = zip_fopen(zip_obj, "manifest.json".toStringz, ZIP_FL_ENC_GUESS);
    scope(exit) zip_fclose(manifest_file);

    char[] manifest_content;
    char[BUF_SIZE] buf;
    long res;
    do {
        res = zip_fread(manifest_file, buf.ptr, BUF_SIZE);
        manifest_content ~= buf[0..res];
    } while(res > 0);

    enforce!OdoodException(
        res == 0,
        "Cannot read manifest content from database backup!");

    return parseJSON(manifest_content);
}


/// Test parsing database backup manifest
unittest {
    import unit_threaded.assertions;

    auto manifest = parseDatabaseBackupManifest(
        Path("test-data", "demo-db-backup.zip"));
    manifest["db_name"].get!string.should == "odoo16-odoo-test-backup";
    manifest["version"].get!string.should == "15.0";
    manifest["major_version"].get!string.should == "15.0";
    manifest["pg_version"].get!string.should == "14.0";

    auto manifest_modules = manifest["modules"].object;
    manifest_modules.length.shouldEqual(37);
    manifest_modules["crm"].get!string.shouldEqual("15.0.1.6");
}
