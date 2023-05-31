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
private import odood.lib.odoo.python: guessPySerie;
private import odood.lib.odoo.lodoo: LOdoo;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.server: OdooServer;
private import odood.lib.venv: VirtualEnv;
private import odood.lib.addons.manager: AddonManager;
private import odood.lib.odoo.test: OdooTestRunner;
private import odood.lib.odoo.db_manager: OdooDatabaseManager;
private import odood.lib.git: isGitRepo;

public import odood.lib.project.config:
    ProjectConfigOdoo, ProjectConfigDirectories, DEFAULT_ODOO_REPO;


/** The Odood project.
  * The main entity to manage whole Odood project
  **/
class Project {
    //private const ProjectConfig _config;
    private Nullable!Path _config_path;

    /// Root project directory
    Path _project_root;

    ProjectConfigDirectories _directories;

    ProjectConfigOdoo _odoo;

    VirtualEnv _venv;

    /** Initialize with automatic config discovery
      *
      **/
    static auto loadProject() {
        auto s_config_path = Path.current.searchFileUp("odood.yml");

        // If config is not found in current directory and above,
        // check server-wide config (may be it is installed in server-mode)
        if (s_config_path.isNull && Path("/", "etc", "odood.yml").exists)
            s_config_path = Path("/", "etc", "odood.yml").nullable;

        enforce!OdoodException(
            !s_config_path.isNull,
            "Cannot find OdooD configuration file!");

        return loadProject(s_config_path.get);
    }

    /** Load project from path. Automatically discover odood.yml configuration
      * file and load it.
      *
      * Params:
      *     path = is path to odood config file or path to directory
      *         that contains odood.yml config file
      **/
    static auto loadProject(in Path path) {

        // TODO: convert path to absolute
        //       do we need this? Will be converted in constructor.
        if (path.exists && path.isFile) {
            Node config = dyaml.Loader.fromFile(path.toString()).load();
            return new Project(config, path);
        } else if (path.exists && path.isDir && path.join("odood.yml").exists) {
            auto load_path = path.join("odood.yml");
            Node config = dyaml.Loader.fromFile(load_path.toString()).load();
            return new Project(config, load_path);
        }
        throw new OdoodException(
            "Cannot initialize project. Config not found");
    }

    unittest {
        import unit_threaded.assertions;
        import thepath.utils;

        Path temp_dir = createTempPath();
        scope(exit) temp_dir.remove();

        Project.loadProject(temp_dir).shouldThrow!OdoodException;
    }

    /** Create new project from basic parameters.
      *
      * Params:
      *     project_root = Path to the project root directory
      *     directories = Struct that represents project directories
      *     odoo = Struct that represents Project's Odoo configuration
      *     odoo_serie = Version of Odoo to run
      *     odoo_branch = Name of the branch to get Odoo from
      *     odoo_repo = URL to the repository to get Odoo from
      *     config_path = Path to odood.yml config file
      *     yaml_config = dyaml.Node that represents yaml configuration
      **/
    this(in Path project_root,
            in ProjectConfigDirectories directories,
            in ProjectConfigOdoo odoo,
            in VirtualEnv venv) {
        this._project_root = project_root.toAbsolute;
        this._directories = directories;
        this._odoo = odoo;
        this._venv = venv;
    }

    /// ditto
    this(in Path project_root,
            in ProjectConfigDirectories directories,
            in ProjectConfigOdoo odoo) {
        this(
            project_root,
            directories,
            odoo,
            VirtualEnv(
                project_root.join("venv"),
                guessPySerie(odoo.serie))
        );
    }

    /// ditto
    this(in Path project_root,
            in ProjectConfigDirectories directories,
            in ProjectConfigOdoo odoo,
            in Path config_path) {
        this(project_root, directories, odoo);
        _config_path = Nullable!Path(config_path);
    }

    /// ditto
    this(in Path project_root, in OdooSerie odoo_serie,
            in string odoo_branch, in string odoo_repo) {
        auto root = project_root.toAbsolute;
        auto directories = ProjectConfigDirectories(root);
        this(
            root,
            directories,
            ProjectConfigOdoo(
                root,
                directories,
                odoo_serie,
                odoo_branch,
                odoo_repo),
        );
    }

    /// ditto
    this(in Path project_root, in OdooSerie odoo_serie) {
        this(project_root,
             odoo_serie,
             odoo_serie.toString, 
             DEFAULT_ODOO_REPO);
    }

    /// ditto
    this(in Node yaml_config) {
        this(
            Path(yaml_config["project_root"].as!string),
            ProjectConfigDirectories(yaml_config["directories"]),
            ProjectConfigOdoo(yaml_config["odoo"]),
        );
    }

    /// ditto
    this(in Node yaml_config, in Path config_path) {
        this(yaml_config);
        _config_path = Nullable!Path(config_path);
    }

    /// Path to project config
    const (Path) config_path() const { return _config_path.get; }

    /// Project root directory
    const (Path) project_root() const { return _project_root; }

    /// Project directories
    auto directories() const { return _directories; }

    /// Project odoo info
    auto odoo() const { return _odoo; }

    /// LOdoo instance for this project
    const(LOdoo) lodoo(in bool test_mode=false) const {
        return LOdoo(this, test_mode);
    }

    /** VirtualEnv related to this project.
      * Allows to run commands in convext of virtual environment,
      * install packages, etc
      **/
    auto venv() const { return _venv; }

    /** OdooServer wrapper to manage server of this Odood project
      * Provides basic methods to start/stop/etc odoo server.
      **/
    auto server(in bool test_mode=false) const {
        return OdooServer(this, test_mode);
    }

    /** AddonManager related to this project
      * Allows to manage addons of this project
      **/
    auto addons(in bool test_mode=false) const {
        return AddonManager(this, test_mode);
    }

    /** Return database manager instance, that provides high-level
      * interface to manage Odoo databases
      **/
    auto databases(in bool test_mode=false) const {
        return OdooDatabaseManager(this, test_mode);
    }

    /** Create new test-runner instance.
      **/
    auto testRunner() const { return OdooTestRunner(this); }

    /** Return database wrapper, that allows to interact with database
      * via plain SQL and contains some utility methods.
      *
      * Params:
      *     dbname = name of database to interact with
      **/
    auto dbSQL(in string dbname) const { return databases.get(dbname); }

    /** Save project configuration to specified config file.

        Params:
           path = path to config file to save configuration to.
      **/
    void save(Path path) {
        _config_path = path.nullable;
        auto dumper = dyaml.dumper.dumper();
        dumper.defaultCollectionStyle = dyaml.style.CollectionStyle.block;

        auto out_file = path.openFile("w");
        scope (exit) {
            out_file.close();
        }

        auto yaml_data = Node([
            "project_root": Node(this.project_root.toString),
            "odoo": this.odoo.toYAML(),
            "directories": this.directories.toYAML(),
            "virtualenv": _venv.toYAML(),
        ]);

        infof("Saving Odood config at %s", path);
        dumper.dump(out_file.lockingTextWriter, yaml_data);
    }

    /** Save project configuration to default config file.
      **/
    void save() {
        if (_config_path.isNull)
            save(project_root.join("odood.yml"));
        else
            save(config_path);
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

        // Initialize project directories
        this.project_root.mkdir(true);
        this.directories.initializeDirecotires();

        // Initialize project (install everything needed)
        // TODO: parallelize download of Odoo and installation of virtualenv
        this.installDownloadOdoo();
        this.installVirtualenv(python_version, node_version);
        this.installOdoo();
        this.installOdooConfig(odoo_config);
        // TODO: Automatically save config
    }

    /// ditto
    void initialize() {
        auto odoo_config = this.initOdooConfig();
        initialize(odoo_config);
    }

    /** Update odoo to newer version
      *
      **/
    void updateOdoo() {
        import odood.lib.install;

        // TODO: Add support for backup old odoo sources before updating
        //       Could be useful in case if there were some customizations
        // TODO: Add support for cases when odoo installed via git
        //       In this case it is better to just run git pull
        enforce!OdoodException(
            !this.odoo.path.join(".git").exists,
            "Cannot update odoo that is git repo yet!");

        if (this.odoo.path.exists()) {
            infof("Removing odoo installation at %s", this.odoo.path);
            this.odoo.path.remove();
        }

        this.installDownloadOdoo();
        this.installOdoo();
        infof("Odoo update completed.", this.odoo.path);
    }

    /// Get configuration for Odoo
    auto getOdooConfig() const {
        return this.readOdooConfig;
    }

    /** Run python script for specific database
      **/
    deprecated auto runPyScript(in string dbname, in Path script_path) const {
        return lodoo.runPyScript(dbname, script_path);
    }

    /** Check if database contains demo data.
      **/
    deprecated const(bool) hasDatabaseDemoData(in string dbname) const {
        auto db = dbSQL(dbname);
        scope(exit) db.close;

        return db.hasDemoData();
    }
}

