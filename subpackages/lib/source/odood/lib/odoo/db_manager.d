/** Database manager - provided high-level interface for
  * management of odoo databases.
  **/
module odood.lib.odoo.db_manager;

private import std.logger;
private import std.json;
private import std.format: format;
private import std.exception: enforce;
private import std.typecons;
private import std.datetime.systime: Clock;

private import thepath;
private import theprocess;
private import zipper;

private import odood.lib.project: Project;
private import odood.lib.odoo.lodoo: BackupFormat;
private import odood.lib.odoo.config: parseOdooDatabaseConfig;
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
        //       This could improve performance by avoiding call to python
        //       interpreter. Take into account that database could exist,
        //       but still could not be visible for Odoo.
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

    /** Prepare dump manifest for the database
      **/
    string dumpManifest(in string dbname) const {
        return _project.lodoo(_test_mode).databaseDumpManifext(dbname);
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
        import std.stdio;
        import std.process;
        Path dest = backup_path.exists && backup_path.isDir ?
            backup_path.join(
                generateBackupName(dbname, prefix, backup_format)) :
            backup_path;

        infof("Backing up database %s to %s", dbname, dest);

        auto db_config = _project.parseOdooDatabaseConfig;

        // TODO: Use resolveProgramPath here
        auto pg_dump = Process("pg_dump")
            .withArgs("--no-owner", dbname);
        if (db_config.host)
            pg_dump.setEnv("PGHOST", db_config.host);
        if (db_config.port)
            pg_dump.setEnv("PGPORT", db_config.port);
        if (db_config.user)
            pg_dump.setEnv("PGUSER", db_config.user);
        if (db_config.password)
            pg_dump.setEnv("PGPASSWORD", db_config.password);

        final switch (backup_format) {
            case BackupFormat.zip:
                // Create temp directory
                const auto tmp_dir = createTempPath();
                scope(exit) tmp_dir.remove();

                // Run database backup
                auto dump_pid = pg_dump
                    .addArgs("--file=" ~ tmp_dir.join("dump.sql").toString)
                    .spawn(
                        std.stdio.File("/dev/null"),
                        tmp_dir.join("pg_dump.output.log").openFile("wt"),
                        tmp_dir.join("pg_dump.error.log").openFile("wt"));

                // Copy filestore to temporary directory
                _project.directories.data
                    .join("filestore", dbname)
                    .copyTo(tmp_dir.join("filestore"));

                // Prepare dump manifest
                tmp_dir.join("manifest.json").writeFile(dumpManifest(dbname));

                // Wait database backup completed, and ensure it is ok.
                enforce!OdoodException(
                    dump_pid.wait == 0,
                    "Cannot dump postgresql database.\n%s\nOutput: %s\nErrors: %s\n".format(
                        pg_dump,
                        tmp_dir.join("pg_dump.output.log").readFileText,
                        tmp_dir.join("pg_dump.error.log").readFileText));

                // Save it all in Zip archive
                Zipper(dest, ZipMode.CREATE)
                    .add(tmp_dir.join("filestore"), "filestore")
                    .add(tmp_dir.join("manifest.json"))
                    .add(tmp_dir.join("dump.sql"));
                return dest;
            case BackupFormat.sql:
                // In case of SQL backups, just call pg_dump and let it do its job.
                auto dump_pid = pg_dump
                    .addArgs(
                        "--format=c",
                        "--file=" ~ dest.toString)
                    .execute
                    .ensureOk(true);
                return dest;
        }
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
                backup_path, e.msg);
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

        /* TODO: Implement database restoration in D
         *
         * 1. Restore filestore
         * 2. Restore database
         * 3. Set correct assert rights for filestore if needed
         */

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

