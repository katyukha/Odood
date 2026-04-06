/** Database manager - provided high-level interface for
  * management of odoo databases.
  **/
module odood.lib.odoo.db_manager;

private import std.logger;
private import std.array: array;
private import std.json;
private import std.format: format;
private import std.exception: enforce;
private import std.typecons;
private import std.datetime.systime: Clock;
private import std.algorithm.iteration: filter, map;
private import std.algorithm.searching: canFind;
private import std.string: join, startsWith, chompPrefix, empty, split, strip;

private import thepath;
private import theprocess;
private import darkarchive: DarkArchiveReader, DarkArchiveWriter,
    DarkArchiveFormat, DarkExtractFlags, ExtractParams;

private import odood.lib.project: Project;
private import odood.lib.odoo.config: parseOdooDatabaseConfig, getConfVal;
private import odood.lib.odoo.db: OdooDatabase;
private import odood.lib.odoo.db_utils: openPgConnection;

private import odood.utils.odoo: parseServerSerie;
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

    /** Return list of databases available on this odoo instance.
      *
      * Mirrors Odoo's own list_dbs() logic:
      *
      * - If db_name is set in odoo.conf, return those names directly without
      *   querying PostgreSQL.
      * - Otherwise, query pg_database restricted to databases owned by the
      *   current PostgreSQL user (datdba = current_user).
      *
      * db_filter is intentionally ignored: it is HTTP-specific (used to select
      * a database based on request hostname).
      **/
    string[] list() const {
        import std.algorithm.sorting: sort;

        auto odoo_conf = _project.server.getConfig;

        // If db_name is configured, use it directly — no PG query needed.
        auto db_name_conf = odoo_conf.getConfVal("db_name");
        if (db_name_conf) {
            auto result = db_name_conf.split(",").map!(s => s.strip).array;
            result.sort();
            return result;
        }

        // Query pg_database scoped to databases owned by the current PG user.
        auto db_template = odoo_conf.getConfVal("db_template", "template0");
        auto conn = _project.openPgConnection("postgres");
        auto res = conn.transaction((ref tx) {
            return tx.execParams(
                "SELECT datname FROM pg_database " ~
                "WHERE datdba = (SELECT usesysid FROM pg_user WHERE usename = current_user) " ~
                "  AND NOT datistemplate " ~
                "  AND datallowconn " ~
                "  AND datname != $1 " ~
                "  AND datname != $2 " ~
                "ORDER BY datname",
                "postgres",
                db_template
            );
        });

        string[] databases;
        foreach (row; res)
            databases ~= row[0].as!string;
        return databases;
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
        auto conn = _project.openPgConnection("postgres");
        auto res = conn.transaction((ref tx) {
            return tx.execParams(
                "SELECT EXISTS (" ~
                "    SELECT 1 FROM pg_catalog.pg_database WHERE datname = $1" ~
                ")",
                name);
        });
        return res[0][0].get!bool;
    }

    /** Check if database is initialized as an Odoo database.
      *
      * Checks for the presence of the ir_module_module table, which is
      * created during Odoo's database initialization.
      *
      * Returns:
      *     true if the database contains an Odoo installation, false otherwise.
      **/
    bool isInitialized(in string name) const {
        auto conn = _project.openPgConnection(name);
        auto res = conn.transaction((ref tx) {
            tx.exec("SET LOCAL lock_timeout = '15s'");
            return tx.execParams(
                "SELECT EXISTS (" ~
                "    SELECT 1 FROM information_schema.tables" ~
                "    WHERE table_name = 'ir_module_module'" ~
                "    AND table_schema = 'public'" ~
                ")"
            );
        });
        return res[0][0].get!bool;
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

    /** Ensure database is initialized as an Odoo database.
      *
      * Idempotent: safe to call on every deploy.
      * - If the PG database does not exist, creates it.
      * - If the database is not Odoo-initialized, runs Odoo with
      *   --init=base --stop-after-init to initialize it.
      * - If the database is already initialized, does nothing.
      *
      * Params:
      *     name = database name
      *     demo = load demo data (only effective on first initialization)
      *     lang = language code, e.g. "en_US" (only effective on first initialization)
      **/
    void ensureInitialized(
            in string name,
            in bool demo = false,
            in string lang = null) const {
        if (!exists(name)) {
            infof("Database '%s' does not exist. Creating...", name);
            _createEmptyDB(name);
        }

        if (!isInitialized(name)) {
            infof("Initializing Odoo database '%s'...", name);
            auto swm = _project.server.getConfig.getConfVal(
                "server_wide_modules", "base,web");
            auto runner = _project.server(_test_mode).getServerRunner(
                "-d", name,
                "--max-cron-threads=0",
                "--stop-after-init",
                _project.odoo.serie <= OdooSerie(10) ? "--no-xmlrpc" : "--no-http",
                "--pidfile=",
                "--logfile=%s".format(_project.odoo.logfile),
                "--init=%s".format(swm),
            );
            if (!demo)
                runner.addArgs("--without-demo=all");
            if (lang)
                runner.addArgs("--lang=%s".format(lang));
            runner.execute.ensureOk!OdoodException(true);
            infof("Database '%s' initialized.", name);
        } else {
            infof("Database '%s' is already initialized.", name);
        }
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
        return _project.lodoo(_test_mode).databaseDumpManifest(dbname);
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
        import std.datetime.stopwatch;
        Path dest = backup_path.exists && backup_path.isDir ?
            backup_path.join(
                generateBackupName(dbname, prefix, backup_format)) :
            backup_path;

        infof("Backing up database %s into %s", dbname, dest);

        auto sw = StopWatch(AutoStart.yes);
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
                import std.process : pipe;

                auto writer = DarkArchiveWriter!(DarkArchiveFormat.zip)(dest);
                scope(failure) {
                    // Remove partial ZIP on any failure
                    if (dest.exists) dest.remove();
                }

                // Add filestore directly from data directory (no temp copy)
                auto filestore_path = _project.directories.data
                    .join("filestore", dbname);
                if (filestore_path.exists)
                    writer.addTree(filestore_path, "filestore");

                // Add manifest from memory
                writer.addBuffer("manifest.json",
                    cast(const(ubyte)[]) dumpManifest(dbname));

                // Stream pg_dump directly into ZIP — no temp file for dump.sql
                auto dump_pipe = pipe();

                // pg_dump writes SQL to stdout (no --file= arg),
                // stderr goes to parent's stderr for visibility
                auto dump_pid = pg_dump
                    .spawn(
                        std.stdio.File("/dev/null"),
                        dump_pipe.writeEnd,
                        std.stdio.stderr);

                // Close write end in parent so read sees EOF when pg_dump exits
                dump_pipe.writeEnd.close();

                scope(failure) {
                    dump_pipe.readEnd.close();
                    dump_pid.wait();
                }

                writer.addStream("dump.sql", (scope sink) {
                    ubyte[65536] buf;
                    while (!dump_pipe.readEnd.eof) {
                        auto got = dump_pipe.readEnd.rawRead(buf[]);
                        if (got.length > 0)
                            sink(got);
                    }
                });

                dump_pipe.readEnd.close();

                auto dump_exit_code = dump_pid.wait;
                if (dump_exit_code != 0) {
                    throw new OdoodException(
                        "Cannot dump postgresql database (exit code %s).\n%s"
                        .format(dump_exit_code, pg_dump));
                }

                writer.finish();
                break;
            case BackupFormat.sql:
                // In case of SQL backups, just call pg_dump and let it do its job.
                pg_dump
                    .withArgs(
                        "--format=c",
                        "--file=" ~ dest.toString)
                    .execute
                    .ensureOk(true);
                break;
        }
        sw.stop();
        infof("Back up of database %s into %s completed in %s", dbname, dest, sw.peek);
        return dest;
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
    void _restoreValidateBackupZip(ref DarkArchiveReader!(DarkArchiveFormat.zip) backup, in bool strict) const {
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

        OdooSerie backup_serie = parseServerSerie(manifest["version"].get!string);
        enforce!OdoodException(
            backup_serie.isValid,
            "Cannot restore backup, because backup's server version is not valid (or cannot parse it): %s".format(
                manifest["version"].get!string));
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
    void _restoreSQL(
            in string name,
            in Path backup_path,
            in bool validate_strict=true) const {

        // TODO: Detect format, it may be plain SQL or custom SQL format

        // Use lodoo to restore backup for now
        _project.lodoo(_test_mode).databaseRestore(name, backup_path);
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
        auto odoo_conf = _project.server.getConfig;
        auto db_template = odoo_conf.getConfVal("db_template", "template0");
        auto collate = (db_template == "template0") ? "LC_COLLATE 'C'" : "";

        auto pg_db = _project.openPgConnection("postgres");
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
        auto backup_zip = DarkArchiveReader!(DarkArchiveFormat.zip)(backup_path);
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
            auto reader = DarkArchiveReader!(DarkArchiveFormat.zip)(backup_path);
            reader.processEntries(["dump.sql"],
                (scope ref item) {
                    item.data.readChunks((const(ubyte)[] chunk) {
                        psql_pipe.writeEnd.rawWrite(chunk);
                    });
                });

            psql_pipe.writeEnd.flush();
            psql_pipe.writeEnd.close();
            tracef("Dump of database %s successfully restored!", name);
        });

        auto t_restore_fs = scopedTask(() {
            // Restore filestore
            tracef("Restore filestore for database %s", name);
            fs_path.mkdir(true);
            auto reader = DarkArchiveReader!(DarkArchiveFormat.zip)(backup_path);
            reader.extractTo(fs_path, DarkExtractFlags.defaults,
                (ref ExtractParams params) {
                    if (!params.destPath.startsWith("filestore/"))
                        return false;  // skip non-filestore entries
                    params.destPath = params.destPath.chompPrefix("filestore/");
                    return params.destPath.length > 0;
                });
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

    /** Populate database with automatically generated test data.
      * This feature is supported only for Odoo 16.0+
      *
      * Params:
      *     dbname = name of database to populate
      *     models = names of models to populate
      *     populate_size = Population size. One of: small, medium, large
      **/
    void populate(in string dbname, in string[] models, in string populate_size) const {
        enforce!OdoodException(
            _project.odoo.serie >= 14,
            "'populate' feature is available only for Odoo 14.0+");
        enforce!OdoodException(
            _project.odoo.serie < 18,
            "'populate' feature is not available for Odoo 18.0+, " ~
            "because at this version Odoo switched from generation to duplication of data during population.");
        enforce!OdoodException(
            ["small", "medium", "large"].canFind(populate_size),
            "Populate size could be one of: small, medium, large! Got: %s".format(populate_size));
        infof(
            "Running 'populate' for database %s for models (%s) with size %s...",
            dbname, models.join(", "), populate_size);
        _project.server(_test_mode).getServerRunner("populate")
            .withArgs(
                "-d", dbname,
                "--models=%s".format(models.join(",")),
                "--size=%s".format(populate_size),
            ).execute
            .ensureOk!OdoodException(true);
        infof(
            "Running 'populate' for database %s for models (%s) with size %s. Completed!",
            dbname, models.join(", "), populate_size);
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

    /** Get database by name (as index operation)
      **/
    auto opIndex(in string dbname) const {
        return this.get(dbname);
    }
}

