module odood.utils.odoo.db;

private import std.format: format;
private import std.exception: enforce;
private import std.json: parseJSON;

private import thepath: Path;
private import darkarchive: DarkArchiveReader, DarkArchiveFormat;

private import odood.exception: OdoodException;
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


///
unittest {
    import unit_threaded.assertions;
    import odood.exception: OdoodException;

    Path("backup.zip").detectDatabaseBackupFormat.shouldEqual(BackupFormat.zip);
    Path("backup.sql").detectDatabaseBackupFormat.shouldEqual(BackupFormat.sql);
    Path("/some/path/db-backup-2025-01-01.zip").detectDatabaseBackupFormat.shouldEqual(BackupFormat.zip);
    Path("/some/path/db-backup-2025-01-01.sql").detectDatabaseBackupFormat.shouldEqual(BackupFormat.sql);
    Path("backup.bak").detectDatabaseBackupFormat.shouldThrow!OdoodException;
    Path("backup").detectDatabaseBackupFormat.shouldThrow!OdoodException;
}


/** Parse database backup's manifest
  *
  * Params:
  *     path = path to database backup to parse
  *
  * Returns: JSONValue that contains parsed database backup manifest
  **/
auto parseDatabaseBackupManifest(ref DarkArchiveReader!(DarkArchiveFormat.zip) reader) {
    string manifest_content;
    auto found = reader.processEntries(["manifest.json"],
        (scope ref item) {
            manifest_content = item.data.readText();
        });
    enforce!OdoodException(found > 0,
        "Cannot locate 'manifest.json' inside database backup!");
    return parseJSON(manifest_content);
}

/// ditto
auto parseDatabaseBackupManifest(in Path path) {
    auto reader = DarkArchiveReader!(DarkArchiveFormat.zip)(path);
    return parseDatabaseBackupManifest(reader);
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
