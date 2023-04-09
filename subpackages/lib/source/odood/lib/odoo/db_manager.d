/** Database manager - provided high-level interface for
  * management of odoo databases.
  **/
module odood.lib.odoo.db_manager;

private import std.logger;
private import std.format: format;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.lib.odoo.lodoo: BackupFormat;
private import odood.lib.odoo.db: OdooDatabase;


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

    /** Backup database
      *
      * Params:
      *     dbname = name of database to backup
      *     backup_path = path to store backup
      *     format = Backup format: zip or SQL
      *
      * Returns:
      *     Path where backup was stored.
      **/
    Path backup(
            in string dbname, in Path backup_path,
            in BackupFormat backup_format = BackupFormat.zip) const {
        return _project.lodoo(_test_mode).databaseBackup(dbname, backup_path, backup_format);
    }

    /** Backup database.
      * Path to store backup will be computed automatically.
      *
      * By default, backup will be stored at 'backups' directory inside
      * project root.
      *
      * Params:
      *     dbname = name of database to backup
      *     format = Backup format: zip or SQL
      *
      * Returns:
      *     Path where backup was stored.
      **/
    Path backup(
            in string dbname,
            in BackupFormat backup_format = BackupFormat.zip) const {
        // TODO: Add ability to specify backup path
        import std.datetime.systime: Clock;
        import odood.lib.utils: generateRandomString;

        string dest_name="db-backup-%s-%s.%s.%s".format(
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
                        return "zip";
                }
            })(),
        );
        return backup(
            dbname,
            _project.directories.backups.join(dest_name),
            backup_format);
    }

    /** Restore database
      *
      * Params:
      *     name = name of database to restore
      *     backup_path = path to database backup to restore
      **/
    auto restore(in string name, in Path backup_path) const {
        return _project.lodoo(_test_mode).databaseRestore(name, backup_path);
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

