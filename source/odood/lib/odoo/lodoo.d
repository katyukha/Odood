module odood.lib.odoo.lodoo;

private import thepath: Path;

private import odood.lib.project: ProjectConfig;


enum BackupFormat {
    zip,
    sql,
}


/** Wrapper struct around [LOdoo](https://pypi.org/project/lodoo/)
  * python CLI util
  **/
const struct LOdoo {
    private:
        Path _odoo_conf;
        ProjectConfig _config;

        /** Run lodoo with provided args
          **/
        auto run(in string[] args...) {
            // TODO: user run-in-venv
            return _config.venv.run(
                ["lodoo", "--conf", _odoo_conf.toString] ~ args);
        }

        /** Run lodoo with provided args, raising error
          * in case of non-zero exit status.
          **/
        auto runE(in string[] args...) {
            return _config.venv.runE(
                ["lodoo", "--conf", _odoo_conf.toString] ~ args);
        }

    public:
        @disable this();

        this(in ProjectConfig config, in Path odoo_conf) {
            _odoo_conf = odoo_conf;
            _config = config;
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

            runE(args);
        }

        /** Drop specified database
          **/
        void databaseDrop(in string name) {
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
            runE("db-rename", old_name, new_name);
        }

        /** Copy database
          **/
        void databaseCopy(in string old_name, in string new_name) {
            runE("db-copy", old_name, new_name);
        }

        /** Backup database
          **/
        void databaseBackup(in string name, in Path backup_path,
                            in BackupFormat format = BackupFormat.zip) {
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
            runE("db-restore", name, backup_path.toString);
        }
}
