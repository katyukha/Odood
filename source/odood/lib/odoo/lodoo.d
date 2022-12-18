module odood.lib.odoo.lodoo;

private import thepath: Path;

private import odood.lib.project: ProjectConfig;
private import odood.lib.utils: runCmdE;


/** Wrapper struct around [LOdoo](https://pypi.org/project/lodoo/)
  * python CLI util
  **/
const struct LOdoo {
    private:
        Path _odoo_conf;
        ProjectConfig _config;

        Path _lodoo_path;

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
            auto res = _lodoo_path.runCmdE([
                "--conf", _odoo_conf.toString, "db-list"]);

            return res.output.split("\n").filter!(db => db && db != "").array;
        }


}
