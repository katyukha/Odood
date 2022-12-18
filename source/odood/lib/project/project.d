module odood.lib.project.project;

private import std.stdio;
private import std.exception: enforce;
private import std.format: format;

private import thepath: Path;
private import dini: Ini;

private import odood.lib.exception: OdoodException;
private import odood.lib.odoo.config: initOdooConfig, readOdooConfig;
private import odood.lib.odoo.lodoo: LOdoo;

public import odood.lib.project.config: ProjectConfig;


class Project {
    private ProjectConfig _config;
    private Path _config_path;

    /** Initialize with automatic config discovery
      *
      **/
    this() {
        auto s_config_path = Path.current.searchFileUp("odood.yml");
        enforce!OdoodException(
            !s_config_path.isNull,
            "Cannot find OdooD configuration file!");
        this(s_config_path);
    }

    /** Initialize by path.

        Params:
            path = is path to odood config file or path to directory
                that contains odood.yml config file
      **/
    this(in Path path) {
        if (path.exists && path.isFile) {
            _config.load(path);
        } else if (path.exists && path.isDir && path.join("odood.yml").exists) {
            _config.load(path.join("odood.yml"));
        } else {
            throw new OdoodException(
                "Cannot initialize project. Config not found");
        }
    }

    /** Initialize by provided config

        Params:
            cofnig = instance of project configuration to initialize from.
      **/
    this(in ProjectConfig config, in Path config_path = Path()) {
        _config = config;
        if (config_path.isNull)
            _config_path = config_path;
    }

    /// Project config instance
    @property const (ProjectConfig) config() const { return _config; }

    /// Path to project config
    @property const (Path) config_path() const { return _config_path; }

    /// LOdoo instance for standard config of this project
    @property const(LOdoo) lodoo() const {
        return LOdoo(_config, _config.odoo_conf);
    }

    /** Save project configuration to config file.

        Params:
           path = path to config file to save configuration to.
      **/
    void save(in Path path = Path()) {
        if (path.isNull)
            _config_path =_config.project_root.join("odood.yml");
        else
            _config_path = path;

        _config.save(_config_path);
    }

    /** Initialize project.
      * This will create new project directory and install Odoo there.
      *
      * Params:
      *     odoo_config: INI struct, that represents configuration for Odoo
      **/
    void initialize(ref Ini odoo_config) {
        import odood.lib.install;

        _config.initializeProjectDirs();
        _config.installDownloadOdoo();
        _config.installVirtualenv();
        _config.installOdoo();
        _config.installOdooConfig(odoo_config);
    }

    /// ditto
    void initialize() {
        auto odoo_config = _config.initOdooConfig();
        initialize(odoo_config);
    }

    /** Run the server.
      **/
    void serverRun(in bool detach=false) {
        import odood.lib.server;
        _config.spawnServer(detach);
    }

    /** Is server running
      **/
    bool isServerRunning() {
        import odood.lib.server;
        return _config.isServerRunning;
    }

    /** Stop the server.
      **/
    void serverStop() {
        import odood.lib.server;
        _config.stopServer();
    }

    auto getOdooConfig() {
        return this._config.readOdooConfig;
    }

}

