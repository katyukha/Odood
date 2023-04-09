module odood.lib.odoo.lodoo;

private import std.logger;
private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable;
private static import std.process;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.lib.exception: OdoodException;


/** Supported backup formats
  **/
enum BackupFormat {
    zip,  /// ZIP backup format that includes filestore
    sql,  /// SQL-only backup, that contains only SQL dump
}


/** Wrapper struct around [LOdoo](https://pypi.org/project/lodoo/)
  * python CLI util
  **/
const struct LOdoo {
    private:
        const Project _project;
        const bool _test_mode;

        /// Is test mode enabled?
        @property const(bool) test_mode() const => _test_mode;

        /// Compute config path for lodoo, depending on _test_mode flag
        @property Path odoo_conf_path() const {
            return _test_mode ?
                _project.odoo.testconfigfile : _project.odoo.configfile;
        }

        /** Run lodoo with provided args
          **/
        auto run(
                in string[] args,
                std.process.Config config) {
            tracef("Running LOdoo with args %s", args);
            return _project.venv.run(
                ["lodoo", "--conf", odoo_conf_path.toString] ~ args,
                Nullable!Path.init, // workdir
                null,  // env
                config);
        }

        /// ditto
        auto run(in string[] args...) {
            return run(args, std.process.Config.none);
        }

        /** Run lodoo with provided args, raising error
          * in case of non-zero exit status.
          **/
        auto runE(
                in string[] args,
                std.process.Config config) {
            tracef("Running LOdoo with args %s", args);
            return _project.venv.runE(
                ["lodoo", "--conf", odoo_conf_path.toString] ~ args,
                Nullable!Path.init,  // workdir
                null,  // env
                config);
        }

        /// ditto
        auto runE(in string[] args...) {
            return runE(args, std.process.Config.none);
        }

    public:
        @disable this();

        this(in Project project, in bool test_mode=false) {
            _project = project;
            _test_mode = test_mode;
        }

        /** Return list of databases available on this odoo instance
          **/
        string[] databaseList() {
            import std.array: split, array;
            import std.algorithm.iteration: filter;
            import std.process: Config;
            auto res = runE(["db-list"], Config.stderrPassThrough);
            return res.output.split("\n").filter!(db => db && db != "").array;
        }

        /** Create new Odoo database on this odoo instance
          **/
        auto databaseCreate(in string name, in bool demo=false,
                            in string lang=null, in string password=null,
                            in string country=null) {
            string[] args = ["db-create"];

            if (demo)
                args ~= ["--demo"];
            else
                args ~= ["--no-demo"];

            if (lang)
                args ~= ["--lang", lang];

            if (password)
                args ~= ["--password", password];

            if (country)
                args ~= ["--country", country];

            args ~= [name];

            infof(
                "Creating database %s (%s)",
                name, demo ? "with demo-data" : "without demo-data");
            return runE(args);
        }

        /** Drop specified database
          **/
        auto databaseDrop(in string name) {
            infof("Deleting database %s", name);
            return runE("db-drop", name);
        }

        /** Check if database exists
          **/
        bool databaseExists(in string name) {
            // TODO: replace with project's db wrapper to check if database exists
            //       This could simplify performance by avoiding call to python
            //       interpreter
            auto res = run("db-exists", name);
            return res.status == 0;
        }

        /** Rename database
          **/
        auto databaseRename(in string old_name, in string new_name) {
            infof("Renaming database %s to %s", old_name, new_name);
            return runE("db-rename", old_name, new_name);
        }

        /** Copy database
          **/
        auto databaseCopy(in string old_name, in string new_name) {
            infof("Copying database %s to %s", old_name, new_name);
            return runE("db-copy", old_name, new_name);
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
        Path databaseBackup(
                in string dbname, in Path backup_path,
                in BackupFormat backup_format = BackupFormat.zip) {
            infof("Backing up database %s to %s", dbname, backup_path);
            final switch (backup_format) {
                case BackupFormat.zip:
                    runE("db-backup", dbname, backup_path.toString,
                         "--format", "zip");
                    return backup_path;
                case BackupFormat.sql:
                    runE("db-backup", dbname, backup_path.toString,
                         "--format", "sql");
                    return backup_path;
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
          *     format = Backup format: zip or SQL
          *
          * Returns:
          *     Path where backup was stored.
          **/
        Path databaseBackup(
                in string dbname,
                in BackupFormat backup_format = BackupFormat.zip) {
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
            return databaseBackup(
                dbname,
                _project.directories.backups.join(dest_name),
                backup_format);
        }

        /** Restore database
          **/
        auto databaseRestore(in string name, in Path backup_path) {
            infof("Restoring database %s from %s", name, backup_path);
            return runE("db-restore", name, backup_path.toString);
        }

        /** Update list of addons
          **/
        // TODO: Rename
        auto updateAddonsList(in string dbname) {
            return runE("addons-update-list", dbname);
        }

        /** Uninstall addons
          **/
        auto addonsUninstall(in string dbname, in string[] addon_names) {
            import std.string: join;
            return runE("addons-uninstall", dbname, addon_names.join(","));
        }

        /** Run python script for specific database
          **/
        auto runPyScript(in string dbname, in Path script_path) {
            enforce!OdoodException(
                script_path.exists,
                "Python script %s does not exists!".format(script_path));
            infof(
                "Running SQL script %s for databse %s ...",
                script_path, dbname);
            return runE("run-py-script", dbname, script_path.toString);
        }
}
