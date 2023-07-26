/** Database manager - provided high-level interface for
  * management of odoo databases.
  **/
module odood.lib.odoo.db_manager;

private import std.logger;
private import std.format: format;
private import std.exception: enforce;
private import std.typecons;
private import std.datetime.systime: Clock;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.lib.odoo.lodoo: BackupFormat;
private import odood.lib.odoo.db: OdooDatabase;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils: generateRandomString;
private import odood.exception: OdoodException;

immutable string DEFAULT_BACKUP_PREFIX = "db-backup";


/** Struct designed to manage databases
  *
  * Currently, in most cases it just call lodoo, but possibly in future
  * it will contains own implementation of some logic, maybe some additional
  * logic.
  **/
struct OdooDatabaseManager {
    private const Project _project;
    private const bool _test_mode;

    this(in Project project, in bool test_mode) {
        _project = project;
        _test_mode = test_mode;
    }

    /** Return list of databases available on this odoo instance
      **/
    string[] list() const {
        return _project.lodoo(_test_mode).databaseList();
    }

    /** Create new Odoo database on this odoo instance
      **/
    auto create(in string name, in bool demo=false,
                in string lang=null, in string password=null,
                in string country=null) const {
        return _project.lodoo(_test_mode).databaseCreate(name, demo, lang, password, country);
    }

    /** Drop specified database
      **/
    auto drop(in string name) const {
        return _project.lodoo(_test_mode).databaseDrop(name);
    }

    /** Check if database exists
      **/
    bool exists(in string name) const {
        // TODO: replace with project's db wrapper to check if database exists
        //       This could simplify performance by avoiding call to python
        //       interpreter
        return _project.lodoo(_test_mode).databaseExists(name);
    }

    /** Rename database
      **/
    auto rename(in string old_name, in string new_name) const {
        return _project.lodoo(_test_mode).databaseRename(old_name, new_name);
    }

    /** Copy database
      **/
    auto copy(in string old_name, in string new_name) const {
        return _project.lodoo(_test_mode).databaseCopy(old_name, new_name);
    }

    /** Generate name of backup
      **/
    private string generateBackupName(
            in string dbname,
            in string prefix,
            in BackupFormat backup_format) const {
        return "%s-%s-%s.%s.%s".format(
            prefix,
            dbname,
            "%s-%s-%s".format(
                Clock.currTime.year,
                Clock.currTime.month,
                Clock.currTime.day),
            generateRandomString(4),
            (() {
                final switch (backup_format) {
                    case BackupFormat.zip:
                        return "zip";
                    case BackupFormat.sql:
                        return "sql";
                }
            })(),
        );
    }

    /** Backup database
      *
      * Params:
      *     dbname = name of database to backup
      *     backup_path = path to store backup
      *     format = Backup format: zip or SQL
      *     prefix = prefix to be used to generate name of backup, when
      *         backup_path is directory
      *
      * Returns:
      *     Path where backup was stored.
      **/
    Path backup(
            in string dbname, in Path backup_path,
            in BackupFormat backup_format = BackupFormat.zip,
            in string prefix = DEFAULT_BACKUP_PREFIX) const {
        Path dest = backup_path.exists && backup_path.isDir ?
            backup_path.join(
                generateBackupName(dbname, prefix, backup_format)) :
            backup_path;

        return _project.lodoo(_test_mode).databaseBackup(
            dbname, dest, backup_format);
    }

    /** Backup database.
      * Path to store backup will be computed automatically.
      *
      * By default, backup will be stored at 'backups' directory inside
      * project root.
      *
      * Params:
      *     dbname = name of database to backup
      *     prefix = prefix for name of database backup
      *     format = Backup format: zip or SQL
      *
      * Returns:
      *     Path where backup was stored.
      **/
    Path backup(
            in string dbname,
            in string prefix,
            in BackupFormat backup_format = BackupFormat.zip) const {
        return backup(
            dbname, _project.directories.backups, backup_format, prefix);
    }

    /// ditto
    Path backup(
            in string dbname,
            in BackupFormat backup_format = BackupFormat.zip) const {
        return backup(dbname, _project.directories.backups, backup_format);
    }

    /** Validate backup provided for restore method.
      *
      * Params:
      *     backup_path = Path to database backup to validate
      *     strict = if set to true, then will raise error if backup
      *         requires addons that are not available in this odoo install.
      **/
    void _restoreValidateBackup(in Path backup_path, in bool strict) const {
        import std.json;
        import std.string: join;
        import std.algorithm: canFind;
        import odood.utils.odoo.db: parseDatabaseBackupManifest;

        enforce!OdoodException(
                backup_path.exists,
                "Cannot restore! Backup %s does not exists!".format(backup_path));

        enforce!OdoodException(
            [".sql", ".zip"].canFind(backup_path.extension),
            "Cannot restore database backup %s" ~ backup_path.toString ~
            ": unsupported backup format!\n" ~
            "Supported backup formats: .zip, .sql");

        if (backup_path.extension == ".sql")
            // No validation available for SQL
            return;

        JSONValue manifest;
        try {
            manifest = parseDatabaseBackupManifest(backup_path);
        } catch (OdoodException e) {
            warningf(
                "Cannot find/parse backup (%s) manifest: %s",
                backup_path, e);
            // TODO: try to guess if it is SQL backup or ZIP backup, and
            //       do correct validation;
            return;
        }

        OdooSerie backup_serie = manifest["version"].get!string;
        enforce!OdoodException(
            backup_serie == _project.odoo.serie,
            "Cannot restore backup %s: backup version %s do not match odoo version %s".format(
                backup_path, backup_serie, _project.odoo.serie));

        // TODO: check PG version

        string[] missing_addons;
        foreach(string name, ver; manifest["modules"]) {
            const auto addon = _project.addons(_test_mode).getByName(name);
            if (addon.isNull) {
                missing_addons ~= name;
                warningf(
                    "Addon %s is not available, but used in backup %s",
                    name, backup_path);
            }
        }
        if (strict && missing_addons.length > 0)
            throw new OdoodException(
                "Cannot restore backup %s, because following addons missing:\n%s".format(
                    backup_path, missing_addons.join("\n")));

    }

    /** Restore database
      *
      * Params:
      *     name = name of database to restore
      *     backup_path = path to database backup to restore
      *     backup_name = name of backup located in standard backup location or path to backup as string.
      *     validate_strict = if set to true,
      *         then raise error if backup is not valid,
      *         otherwise only warning will be emited to log.
      **/
    auto restore(
            in string name,
            in Path backup_path,
            in bool validate_strict=true) const {
        _restoreValidateBackup(backup_path, validate_strict);

        return _project.lodoo(_test_mode).databaseRestore(name, backup_path);
    }

    /// ditto
    auto restore(
            in string name,
            in string backup_name,
            in bool validate_strict=true) const {
        Path backup_path = Path(backup_name);
        if (!backup_path.exists)
            // Try to search for backup in standard backup directory.
            backup_path = _project.directories.backups.join(backup_name);
        return restore(name, backup_path, validate_strict);
    }

    /** Return database wrapper, that allows to interact with database
      * via plain SQL and contains some utility methods.
      *
      * Params:
      *     dbname = name of database to interact with
      **/
    auto get(in string dbname) const {
        return OdooDatabase(_project, dbname);
    }
}

