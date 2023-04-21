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
private import odood.lib.odoo.serie: OdooSerie;


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


/// Resolve version conflict in provided manifest content.
string fixVersionConflictImpl(in string manifest_content, in OdooSerie serie) {
    import std.regex;
    import semver;

    auto immutable RE_CONFLICT = ctRegex!(
        `^<<<<<<< HEAD\n` ~
        `(?P<head>\s+["']version["']:\s["'](?P<headserie>\d+\.\d+)\.(?P<headver>\d+\.\d+\.\d+)["'],\n)` ~
        `=======\n` ~
        `(?P<changekey>\s+["']version["']:\s)(?P<changequote>["'])(?P<changeserie>\d+\.\d+)\.(?P<changever>\d+\.\d+\.\d+)["'],\n` ~
        `>>>>>>> .*\n`, "m");

    // function that is responsible for replace
    string fn_replace(Captures!(string) captures) {
        OdooSerie head_serie = captures["headserie"];
        SemVer head_version = captures["headver"];

        OdooSerie change_serie = captures["changeserie"];
        SemVer change_version = captures["changever"];

        auto new_ver = change_version > head_version ? change_version : head_version;

        // TODO: find better workaround
        assert(new_ver.isValid, "New version is not valid");

        return "%s%s%s.%s%s,\n".format(
            captures["changekey"],
            captures["changequote"],
            serie.toString,
            new_ver.toString,
            captures["changequote"],
        );
    }

    return manifest_content.replaceAll!(fn_replace)(RE_CONFLICT);
}

unittest {
    import unit_threaded.assertions;
    string manifest_content = `{
    'name': "Bureaucrat Helpdesk Pro [Obsolete]",
    'author': "Center of Research and Development",
    'website': "https://crnd.pro",
<<<<<<< HEAD
    'version': '15.0.1.10.0',
=======
    'version': '16.0.1.9.0',
>>>>>>> d1d911566 (Init port)
    'category': 'Helpdesk',
}`;

    manifest_content.fixVersionConflictImpl(OdooSerie(16)).shouldEqual(`{
    'name': "Bureaucrat Helpdesk Pro [Obsolete]",
    'author': "Center of Research and Development",
    'website': "https://crnd.pro",
    'version': '16.0.1.10.0',
    'category': 'Helpdesk',
}`);

}


/// Resove version conflict in manifest file by provided path
void fixVersionConflict(in Path manifest_path, in OdooSerie serie) {
    infof("Fixing version conflict in manifest: %s", manifest_path);
    string manifest_content = manifest_path.readFileText()
        .fixVersionConflictImpl(serie);
    manifest_path.writeFile(manifest_content);
}
