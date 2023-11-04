module odood.lib.odoo.lodoo;

private import std.logger;
private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable;
private static import std.process;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.utils: generateRandomString;
private import odood.utils.odoo.db: BackupFormat;
private import odood.exception: OdoodException;


/** Wrapper struct around [LOdoo](https://pypi.org/project/lodoo/)
  * python CLI util
  **/
const struct LOdoo {
    private:
        const Project _project;
        const bool _test_mode;

        /// Is test mode enabled?
        const(bool) test_mode() const => _test_mode;

        /// Compute config path for lodoo, depending on _test_mode flag
        Path odoo_conf_path() const {
            return _test_mode ?
                _project.odoo.testconfigfile : _project.odoo.configfile;
        }

        auto runner() const {
            auto process = _project.venv.runner()
                .addArgs("lodoo", "--conf", odoo_conf_path.toString);
            if (_project.odoo.server_user)
                process.setUser(_project.odoo.server_user);
            return process;
        }

        /** Run lodoo with provided args
          **/
        auto run(
                in string[] args,
                std.process.Config config) {
            tracef("Running LOdoo with args %s", args);
            auto process = runner().addArgs(args);
            if (config != std.process.Config.none)
                process.setConfig(config);
            return process.execute();
        }

        /// ditto
        auto run(in string[] args...) {
            return run(args, std.process.Config.none);
        }

        /** Run lodoo with provided args, raising error
          * in case of non-zero exit status.
          **/
        auto runE(in string[] args, std.process.Config config) {
            return run(args, config).ensureStatus!OdoodException(true);
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
        deprecated(
            "Because this method is not reliable, Odoo hides output of pgdump, " ~
            "it is difficult to understand what happened in case of errors. " ~
            "Thus Odood now have its own implementation of backup at " ~
            "`project.databases.backup` method.")
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
        deprecated(
            "Because this method is not reliable, Odoo hides output of pgdump, " ~
            "it is difficult to understand what happened in case of errors. " ~
            "Thus Odood now have its own implementation of backup at " ~
            "`project.databases.backup` method.")
        Path databaseBackup(
                in string dbname,
                in BackupFormat backup_format = BackupFormat.zip) {
            import std.datetime.systime: Clock;

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
        deprecated auto databaseRestore(in string name, in Path backup_path) {
            infof("Restoring database %s from %s", name, backup_path);
            return runE("db-restore", name, backup_path.toString);
        }

        auto databaseDumpManifext(in string name) {
            return runE("db-dump-manifest", name).output;
        }

        /** Update list of addons
          *
          * Params:
          *     dbname = name of database to update addons list for
          *     ignore_error = if set to true, then no exception will be raised
          *         if lodoo returned non-zero exit code, otherwise
          *         OdoodException will be thrown if lodoo
          *         command addons-update-list failed with non-zero exit code
          **/
        auto addonsUpdateList(in string dbname, in bool ignore_error=false) {
            if (ignore_error)
                return run("addons-update-list", dbname);
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
            import std.datetime.stopwatch;
            enforce!OdoodException(
                script_path.exists,
                "Python script %s does not exists!".format(script_path));
            infof(
                "Running python script %s for databse %s ...",
                script_path, dbname);
            auto sw = StopWatch(AutoStart.yes);
            auto result = run("run-py-script", dbname, script_path.toString);
            sw.stop();
            enforce!OdoodException(
                result.status == 0,
                "Python script %s for database %s failed with error (exit-code)!\nOutput: %s".format(
                    script_path, dbname, result.output));
            infof(
                "Python script %s for database %s completed in %s:\nOutput: %s".format(
                    script_path, dbname, sw.peek, result.output));
            return result;
        }
}
