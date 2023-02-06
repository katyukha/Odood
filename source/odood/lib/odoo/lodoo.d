module odood.lib.odoo.lodoo;

private import std.logger;
private import thepath: Path;

private import odood.lib.project: Project;


enum BackupFormat {
    zip,
    sql,
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
        void databaseCreate(in string name, in bool demo=false,
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
            runE(args);
        }

        /** Drop specified database
          **/
        void databaseDrop(in string name) {
            infof("Deleting database %s", name);
            runE("db-drop", name);
        }

        /** Check if database eixsts
          **/
        bool databaseExists(in string name) {
            auto res = run("db-exists", name);
            return res.status == 0;
        }

        /** Rename database
          **/
        void databaseRename(in string old_name, in string new_name) {
            infof("Renaming database %s to %s", old_name, new_name);
            runE("db-rename", old_name, new_name);
        }

        /** Copy database
          **/
        void databaseCopy(in string old_name, in string new_name) {
            infof("Copying database %s to %s", old_name, new_name);
            runE("db-copy", old_name, new_name);
        }

        /** Backup database
          **/
        void databaseBackup(in string name, in Path backup_path,
                            in BackupFormat format = BackupFormat.zip) {
            infof("Backing up database %s to %s", name, backup_path);
            final switch (format) {
                case BackupFormat.zip:
                    runE("db-backup", name, backup_path.toString,
                         "--format", "zip");
                    break;
                case BackupFormat.sql:
                    runE("db-backup", name, backup_path.toString,
                         "--format", "sql");
                    break;
            }
        }

        /** Restore database
          **/
        void databaseRestore(in string name, in Path backup_path) {
            infof("Restoring database %s from %s", name, backup_path);
            runE("db-restore", name, backup_path.toString);
        }

        /** Update list of addons
          **/
        // TODO: Rename
        void updateAddonsList(in string dbname) {
            runE("addons-update-list", dbname);
        }

        /** Uninstall addons
          **/
        void addonsUninstall(in string dbname, in string[] addon_names) {
            import std.string: join;
            runE("addons-uninstall", dbname, addon_names.join(","));
        }
}
