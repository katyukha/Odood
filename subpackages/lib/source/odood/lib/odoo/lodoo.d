module odood.lib.odoo.lodoo;

private import std.logger;
private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable;
private import std.array: split, array, join;
private import std.algorithm.iteration: filter;
private import std.process: Config;
private static import std.process;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.utils: generateRandomString;
private import odood.utils.odoo.db: BackupFormat;
private import odood.exception: OdoodException;

// TODO: Do we need all this for Odoo 17+? It seems that it has built-in commands
//       for database management
//       Thus, may be it have sense to use Odoo standard commands when possible.

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
    public:
        @disable this();

        this(in Project project, in bool test_mode=false) {
            _project = project;
            _test_mode = test_mode;
        }

        /** Return list of databases available on this odoo instance
          **/
        string[] databaseList() {
            return runner
                .addArgs("db-list")
                .withFlag(Config.stderrPassThrough)
                .execute()
                .ensureOk!OdoodException(true)
                .output.split("\n").filter!(db => db && db != "").array;
        }

        /** Create new Odoo database on this odoo instance
          **/
        void databaseCreate(in string name, in bool demo=false,
                            in string lang=null, in string password=null,
                            in string country=null) {
            auto cmd = runner.addArgs(
                "db-create",
                demo ? "--demo" : "--no-demo",
            );

            if (lang)
                cmd.addArgs("--lang", lang);

            if (password)
                cmd.addArgs("--password", password);

            if (country)
                cmd.addArgs("--country", country);

            cmd.addArgs(name);

            infof(
                "Creating database %s (%s)",
                name, demo ? "with demo-data" : "without demo-data");
            cmd.execute.ensureOk!OdoodException(true);
        }

        /** Drop specified database
          **/
        void databaseDrop(in string name) {
            infof("Deleting database %s", name);
            runner
                .addArgs("db-drop", name)
                .execute
                .ensureOk!OdoodException(true);
        }

        /** Check if database exists
          **/
        bool databaseExists(in string name) {
            return runner
                .addArgs("db-exists", name)
                .execute()
                .status == 0;
        }

        /** Rename database
          **/
        void databaseRename(in string old_name, in string new_name) {
            infof("Renaming database %s to %s", old_name, new_name);
            runner
                .addArgs("db-rename", old_name, new_name)
                .execute
                .ensureOk!OdoodException(true);
        }

        /** Copy database
          **/
        auto databaseCopy(in string old_name, in string new_name) {
            infof("Copying database %s to %s", old_name, new_name);
            runner
                .addArgs("db-copy", old_name, new_name)
                .execute
                .ensureOk!OdoodException(true);
        }

        /** Restore database
          **/
        deprecated void databaseRestore(in string name, in Path backup_path) {
            infof("Restoring database %s from %s", name, backup_path);
            runner
                .addArgs("db-restore", name, backup_path.toString)
                .execute
                .ensureOk!OdoodException(true);

        }

        auto databaseDumpManifest(in string name) {
            return runner
                .addArgs("db-dump-manifest", name)
                .withFlag(Config.stderrPassThrough)
                .execute
                .ensureOk!OdoodException(true)
                .output;
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
        void addonsUpdateList(in string dbname, in bool ignore_error=false) {
            auto res = runner
                .addArgs("addons-update-list", dbname)
                .execute;
            if (!ignore_error)
                res.ensureOk!OdoodException(true);
        }

        /** Uninstall addons
          **/
        void addonsUninstall(in string dbname, in string[] addon_names) {
            runner
                .addArgs("addons-uninstall", dbname, addon_names.join(","))
                .execute
                .ensureOk!OdoodException(true);
        }

        /** Run python script for specific database
          **/
        auto runPyScript(in string dbname, in Path script_path) {
            import std.datetime.stopwatch;
            import std.process: wait;
            enforce!OdoodException(
                script_path.exists,
                "Python script %s does not exists!".format(script_path));
            infof(
                "Running python script %s for databse %s ...",
                script_path, dbname);
            auto sw = StopWatch(AutoStart.yes);

            // NOTE: This way, script will print on standard stderr/stdout
            auto pid = runner.addArgs("run-py-script", dbname, script_path.toString)
                .spawn;
            // TODO: Find a way to capture script output. Do we need output?
            auto result = pid.wait;
            sw.stop();
            enforce!OdoodException(
                result == 0,
                "Python script %s for database %s failed with error (exit-code): %s!".format(
                    script_path, dbname));
            infof(
                "Python script %s for database %s completed in %s.".format(
                    script_path, dbname, sw.peek));
            return result;
        }

        void recomputeField(in string dbname, in string model, in string[] fields) const {
            import std.algorithm.iteration;
            this.runner
                .addArgs("odoo-recompute", dbname, model)
                .addArgs(fields.map!(f => ["-f", f]).fold!((a, b) => a ~ b).array)
                .execute
                .ensureOk!OdoodException(true);
        }

        void generatePot(in string dbname, in string addon, in bool remove_dates=false) const {
            infof("Generating POT file for %s database for %s addon", dbname, addon);
            auto runner = this.runner
                .addArgs("tr-generate-pot-file");
            if (remove_dates)
                runner.addArgs("--remove-dates");
            runner.addArgs(dbname, addon);
            tracef("Running command %s", runner.toString);
            runner
                .execute
                .ensureOk!OdoodException(true);
        }
}
