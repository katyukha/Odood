module odood.utils.odoo.db;

private import std.logger;
private import std.string: toStringz, fromStringz, strip;
private import std.format: format;
private import std.exception: enforce;
private import std.json;

private import thepath: Path;

private import odood.exception: OdoodException;
private import odood.utils.zip;
private import odood.utils.odoo.serie: OdooSerie;


/** Supported backup formats
  **/
enum BackupFormat {
    zip,  /// ZIP backup format that includes filestore
    sql,  /// SQL-only backup, that contains only SQL dump
}


/** Try to detect backup format from path to backup file.
  *
  * Params:
  *     path = path to backup
  *
  * Returns: detected BackupFormat
  *
  **/
auto detectDatabaseBackupFormat(in Path path) {
    switch(path.extension) {
        case ".zip":
            return BackupFormat.zip;
        case ".sql":
            return BackupFormat.sql;
        default:
            throw new OdoodException(
                    "Cannot detect backup format for %s".format(path));
    }
}

/** Parse database backup's manifest
  *
  * Params:
  *     path = path to database backup to parse
  *
  * Returns: JSONValue that contains parsed database backup manifest
  **/
auto parseDatabaseBackupManifest(Zipper zip) {
    enforce!OdoodException(
        zip.hasEntry("manifest.json"),
        "Cannot locate 'manifest.json' inside database backup!");
    char[] manifest_content = zip["manifest.json"].readFull!char();
    return parseJSON(manifest_content);
}

/// ditto
auto parseDatabaseBackupManifest(in Path path) {
    auto zip = Zipper(path);
    return parseDatabaseBackupManifest(zip);
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
