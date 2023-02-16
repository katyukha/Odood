module odood.lib.odoo.lodoo;

private import std.logger;
private import std.exception: enforce;
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
        const Path _odoo_conf;
        const Project _project;

        /** Run lodoo with provided args
          **/
        auto run(in string[] args...) {
            tracef("Running LOdoo with args %s", args);
            return _project.venv.run(
                ["lodoo", "--conf", _odoo_conf.toString] ~ args);
        }

        /** Run lodoo with provided args, raising error
          * in case of non-zero exit status.
          **/
        auto runE(in string[] args...) {
            tracef("Running LOdoo with args %s", args);
            return _project.venv.runE(
                ["lodoo", "--conf", _odoo_conf.toString] ~ args);
        }

    public:
        @disable this();

        this(in Project project, in Path odoo_conf) {
            _odoo_conf = odoo_conf;
            _project = project;
        }

        /** Return list of databases available on this odoo instance
          **/
        string[] databaseList() {
            import std.array: split, array;
            import std.algorithm.iteration: filter;
            auto res = runE("db-list");
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

        /** Check if database eixsts
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
          **/
        auto databaseBackup(in string name, in Path backup_path,
                            in BackupFormat format = BackupFormat.zip) {
            infof("Backing up database %s to %s", name, backup_path);
            final switch (format) {
                case BackupFormat.zip:
                    return runE("db-backup", name, backup_path.toString,
                         "--format", "zip");
                case BackupFormat.sql:
                    return runE("db-backup", name, backup_path.toString,
                         "--format", "sql");
            }
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
                "Script does not exists");
            return runE("run-py-script", dbname, script_path.toString);
        }
}
