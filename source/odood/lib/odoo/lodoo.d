module odood.lib.odoo.lodoo;

private import thepath: Path;

private import odood.lib.project: ProjectConfig;
//private import odood.lib.utils: runCmd, runCmdE;
private import odood.lib.venv: runInVenv, runInVenvE;


/** Wrapper struct around [LOdoo](https://pypi.org/project/lodoo/)
  * python CLI util
  **/
const struct LOdoo {
    private:
        Path _odoo_conf;
        ProjectConfig _config;

        /// Run lodoo with provided args
        auto run(in string[] args...) {
            // TODO: user run-in-venv
            return _config.runInVenv(
                ["lodoo", "--conf", _odoo_conf.toString] ~ args);
        }

        /** Run lodoo with provided args, raising error
          * in case of non-zero exit status.
          **/
        auto runE(in string[] args...) {
            return _config.runInVenvE(
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
        string[] listDatabases() {
            import std.array: split, array;
            import std.algorithm.iteration: filter;
            auto res = runE("db-list");
            return res.output.split("\n").filter!(db => db && db != "").array;
        }

        /** Create new Odoo database on this odoo instance
          **/
        void createDatabase(in string name, in bool demo=false,
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
        void dropDatabase(in string name) {
            runE("db-drop", name);
        }

        /** Check if database eixsts
          **/
        bool isDatabaseExists(in string name) {
            auto res = run("db-exists", name);
            return res.status == 0;
        }
}
