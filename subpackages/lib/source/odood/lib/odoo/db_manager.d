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
private import std.algorithm.searching: canFind;
private import std.string: join, startsWith, chompPrefix, empty;

private import thepath;
private import theprocess;
private import zipper;

private import odood.lib.project: Project;
private import odood.lib.odoo.config: parseOdooDatabaseConfig;
private import odood.lib.odoo.db: OdooDatabase;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.odoo.db: detectDatabaseBackupFormat, BackupFormat;
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
                pg_dump
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

    /** Validate backup (ZIP format) provided for restore method.
      *
      * Params:
      *     backup_path = Path to database backup to validate
      *     strict = if set to true, then will raise error if backup
      *         requires addons that are not available in this odoo install.
      **/
    void _restoreValidateBackupZip(Zipper backup, in bool strict) const {
        import odood.utils.odoo.db: parseDatabaseBackupManifest;

        JSONValue manifest;
        try {
            manifest = parseDatabaseBackupManifest(backup);
        } catch (OdoodException e) {
            warningf(
                "Cannot find/parse backup manifest: %s", e.msg);
            // TODO: try to guess if it is SQL backup or ZIP backup, and
            //       do correct validation;
            return;
        }

        OdooSerie backup_serie = manifest["version"].get!string;
        enforce!OdoodException(
            backup_serie == _project.odoo.serie,
            "Cannot restore backup: backup version %s do not match odoo version %s".format(
                backup_serie, _project.odoo.serie));

        // TODO: check PG version. Implement it in peque

        string[] missing_addons;
        foreach(string name, ver; manifest["modules"]) {
            const auto addon = _project.addons(_test_mode).getByName(name);
            if (addon.isNull) {
                missing_addons ~= name;
                warningf(
                    "Addon %s is not available, but used in backup", name);
            }
        }
        if (strict && missing_addons.length > 0)
            throw new OdoodException(
                "Cannot restore backup, because following addons missing:\n%s".format(
                    missing_addons.join("\n")));
    }

    /** Restore database from backup of old v7 SQL format
      *
      * Params:
      *     name = name of database to restore
      *     backup_path = path to database backup to restore
      *     backup_name = name of backup located in standard backup location or path to backup as string.
      *     validate_strict = if set to true,
      *         then raise error if backup is not valid,
      *         otherwise only warning will be emited to log.
      **/
    auto _restoreSQL(
            in string name,
            in Path backup_path,
            in bool validate_strict=true) const {

        // TODO: Detect format, it may be plain SQL or custom SQL format

        // Use lodoo to restore backup for now
        return _project.lodoo(_test_mode).databaseRestore(name, backup_path);
    }

    /** Create empty database before restoration
      *
      * Params:
      *     name = name of database to create
      **/
    void _createEmptyDB(in string name) const {
        import std.uni;
        import peque.exception;
        import odood.lib.odoo.config: getConfVal;
        auto odoo_conf = _project.getOdooConfig();
        auto db_template = odoo_conf.getConfVal("db_template", "template0");
        auto collate = (db_template == "template0") ? "LC_COLLATE 'C'" : "";

        auto pg_db = this.get("postgres").connection;
        pg_db.exec(
            "CREATE DATABASE \"%s\" ENCODING 'unicode' %s TEMPLATE %s".format(
                name, collate, db_template));

        // Install 'unaccent' extension if needed
        if (odoo_conf.getConfVal("unaccent").toLower == "true") {
            try {
                auto db = this.get(name);
                db.runSQLQuery("CREATE EXTENSION IF NOT EXISTS unaccent");
            } catch (PequeException e) {
                // Do nothing
            }
        }
    }

    /** Restore database from new backup of ZIP format
      *
      * Params:
      *     name = name of database to restore
      *     backup_path = path to database backup to restore
      *     backup_name = name of backup located in standard backup location or path to backup as string.
      *     validate_strict = if set to true,
      *         then raise error if backup is not valid,
      *         otherwise only warning will be emited to log.
      **/
    void _restoreZIP(
            in string name,
            in Path backup_path,
            in bool validate_strict=true) const {
        import std.parallelism;
        auto backup_zip = Zipper(backup_path);
        _restoreValidateBackupZip(backup_zip, validate_strict);

        infof("Restoring database %s from %s", name, backup_path);

        _createEmptyDB(name);

        // Create and set correct access rights for "filestore" dir if needed
        if (!_project.odoo.server_user.empty && !_project.directories.data.join("filestore").exists) {
            _project.directories.data.join("filestore").mkdir(true);
            _project.directories.data.join("filestore").chown(username: _project.odoo.server_user, recursive: true);
        }

        auto fs_path = _project.directories.data.join("filestore", name);
        scope(failure) {
            // TODO: Use pure SQL to check if db exists and for cleanup
            if (this.exists(name)) this.drop(name);
            if (fs_path.exists()) fs_path.remove();
        }

        // Prepare tasks
        auto t_restore_db = scopedTask(() {
            import std.process: wait, pipe;
            import std.stdio;

            auto zip = Zipper(backup_path);
            auto dump = zip.entry("dump.sql");

            auto psql_pipe = pipe();
            scope(exit) psql_pipe.close();
            auto psql_pid = _project.psql
                .withArgs(
                    "--file=-",
                    "-q",
                    "--dbname=%s".format(name))
                .spawn(
                    psql_pipe.readEnd,
                    File("/dev/null", "wt"),
                    std.stdio.stderr,
                );
            scope(exit) psql_pid.wait();

            tracef("Restoring database %s dump", name);
            dump.readByChunk!char(
                (scope const char[] chunk, in ulong chunk_size) {
                    psql_pipe.writeEnd.write(chunk[0 .. chunk_size]);
                });

            psql_pipe.writeEnd.flush();
            psql_pipe.writeEnd.close();
            tracef("Dump of database %s successfully restored!", name);
        });

        auto t_restore_fs = scopedTask(() {
            // Restore filestore
            tracef("Restore filestore for database %s", name);
            auto zip = Zipper(backup_path);
            fs_path.mkdir(true);
            foreach(entry; zip.entries) {
                if (entry.name.startsWith("filestore/")) {
                    entry.unzipTo(
                        fs_path.join(
                            entry.name.chompPrefix("filestore/")));
                }
            }
            if (_project.odoo.server_user) {
                // Set correct ownership for database's filestore
                fs_path.chown(username: _project.odoo.server_user, recursive: true);
            }
            tracef("Filestore for database %s was successfully restored", name);
        });

        // Run tasks
        t_restore_db.executeInNewThread();
        t_restore_fs.executeInNewThread();

        // Wait tasks
        t_restore_db.yieldForce();
        t_restore_fs.yieldForce();

        infof("Database %s restored from backup %s", name, backup_path);
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
    void restore(
            in string name,
            in Path backup_path,
            in bool validate_strict=true) const {
        enforce!OdoodException(
                backup_path.exists,
                "Cannot restore! Backup %s does not exists!".format(backup_path));

        auto backup_format = backup_path.detectDatabaseBackupFormat;

        final switch(backup_format) {
            case BackupFormat.zip:
                _restoreZIP(name, backup_path, validate_strict);
                break;
            case BackupFormat.sql:
                _restoreSQL(name, backup_path, validate_strict);
                break;
        }
    }

    /// ditto
    void restore(
            in string name,
            in string backup_name,
            in bool validate_strict=true) const {
        Path backup_path = Path(backup_name);
        if (!backup_path.exists)
            // Try to search for backup in standard backup directory.
            backup_path = _project.directories.backups.join(backup_name);
        restore(name, backup_path, validate_strict);
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

