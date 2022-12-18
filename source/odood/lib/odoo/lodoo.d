module odood.lib.odoo.lodoo;

private import thepath: Path;

private import odood.lib.project: ProjectConfig;
private import odood.lib.utils: runCmd, runCmdE;


/** Wrapper struct around [LOdoo](https://pypi.org/project/lodoo/)
  * python CLI util
  **/
const struct LOdoo {
    private:
        Path _odoo_conf;
        ProjectConfig _config;

        Path _lodoo_path;

        /// Run lodoo with provided args
        auto run(in string[] args...) {
            return _lodoo_path.runCmd(["--conf", _odoo_conf.toString] ~ args);
        }

        /** Run lodoo with provided args, raising error
          * in case of non-zero exit status.
          **/
        auto runE(in string[] args...) {
            return _lodoo_path.runCmdE(["--conf", _odoo_conf.toString] ~ args);
        }

    public:
        @disable this();

        this(in ProjectConfig config, in Path odoo_conf) {
            _odoo_conf = odoo_conf;
            _config = config;
            _lodoo_path = config.venv_dir.join("bin", "lodoo");
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
}
