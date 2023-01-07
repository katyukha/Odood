module odood.lib.project.project;

private import std.stdio;
private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable, nullable;
private import std.logger;

private import thepath: Path;
private import dini: Ini;
private import dyaml;

private import odood.lib.exception: OdoodException;
private import odood.lib.odoo.config: initOdooConfig, readOdooConfig;
private import odood.lib.odoo.lodoo: LOdoo;
private import odood.lib.server: OdooServer;
private import odood.lib.addon_manager: AddonManager;
private import odood.lib.repository: AddonRepository, cloneRepo;
private import odood.lib.odoo.test: OdooTestRunner;

public import odood.lib.project.config: ProjectConfig;


/** The Odood project.
  * The main entity to manage whole Odood project
  **/
class Project {
    private ProjectConfig _config;
    private Nullable!Path _config_path;

    /** Initialize with automatic config discovery
      *
      **/
    this() {
        auto s_config_path = Path.current.searchFileUp("odood.yml");
        enforce!OdoodException(
            !s_config_path.isNull,
            "Cannot find OdooD configuration file!");
        this(s_config_path.get);
    }

    /** Initialize by path.

        Params:
            path = is path to odood config file or path to directory
                that contains odood.yml config file
      **/
    this(in Path path) {
        if (path.exists && path.isFile) {
            _config_path = Nullable!Path(path);
            //_config.load(path);
        } else if (path.exists && path.isDir && path.join("odood.yml").exists) {
            _config_path = path.join("odood.yml").nullable;
            //_config.load(path.join("odood.yml"));
        } else {
            throw new OdoodException(
                "Cannot initialize project. Config not found");
        }
        dyaml.Node config_yaml = dyaml.Loader.fromFile(path.toString()).load();
        _config = ProjectConfig(config_yaml);
    }

    /** Initialize by provided config

        Params:
            config = instance of project configuration to initialize from.
      **/
    this(in ProjectConfig config) {
        _config = config;
    }

    /// Project config instance
    @property const (ProjectConfig) config() const { return _config; }

    /// Path to project config
    @property const (Path) config_path() const { return _config_path.get; }

    /// LOdoo instance for standard config of this project
    @property const(LOdoo) lodoo() const {
        return LOdoo(_config, _config.odoo_conf);
    }

    /** VirtualEnv related to this project.
      * Allows to run commands in convext of virtual environment,
      * install packages, etc
      **/
    @property auto venv() const {
        return _config.venv;
    }

    /** OdooServer wrapper to manage server of this Odood project
      * Provides basic methods to start/stop/etc odoo server.
      **/
    @property auto server() const {
        return OdooServer(_config);
    }

    /** AddonManager related to this project
      * Allows to manage addons of this project
      **/
    @property auto addons() const {
        return AddonManager(_config);
    }

    /** Create new test-runner instance.
      **/
    auto testRunner() const {
        return OdooTestRunner(_config);
    }

    /** Save project configuration to config file.

        Params:
           path = path to config file to save configuration to.
      **/
    void save(in Nullable!Path path=Nullable!Path.init) {
        if (!path.isNull)
            _config_path = path;

        if (_config_path.isNull)
            _config.save(_config.project_root.join("odood.yml"));
        else
            _config.save(config_path);
    }

    /** Initialize project.
      * This will create new project directory and install Odoo there.
      *
      * Params:
      *     odoo_config: INI struct, that represents configuration for Odoo
      **/
    void initialize(ref Ini odoo_config,
            in string python_version="auto",
            in string node_version="lts") {
        import odood.lib.install;

        _config.initializeProjectDirs();
        _config.installDownloadOdoo();
        _config.installVirtualenv(python_version, node_version);
        _config.installOdoo();
        _config.installOdooConfig(odoo_config);
    }

    /// ditto
    void initialize() {
        auto odoo_config = _config.initOdooConfig();
        initialize(odoo_config);
    }

    /// Get configuration for Odoo
    auto getOdooConfig() {
        return this._config.readOdooConfig;
    }

    /// Add new repo to project
    void addRepo(in string url, in string branch) {
        auto repo = cloneRepo(_config, url, branch);
        addons.link(repo.path);
    }
}

