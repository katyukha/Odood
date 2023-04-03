module odood.lib.odoo.utils;

private import std.logger;
private import std.string: toStringz, fromStringz, strip;
private import std.format: format;
private import std.exception: enforce;
private import std.json;

private import deimos.zip;

private import thepath: Path;

private import odood.lib.exception: OdoodException;
private import odood.lib.zip;


/** Parse database backup's manifest
  *
  * Params:
  *     path = path to database backup to parse
  *
  * Returns: JSONValue that contains parsed database backup manifest
  **/
auto parse_database_backup_manifest(in Path path) {
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

