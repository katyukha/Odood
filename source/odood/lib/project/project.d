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

public import odood.lib.project.config: ProjectConfigOdoo, ProjectConfigDirectories;


/** The Odood project.
  * The main entity to manage whole Odood project
  **/
class Project {
    //private const ProjectConfig _config;
    private Nullable!Path _config_path;

    /// Root project directory
    Path project_root;

    ProjectConfigDirectories directories;

    ProjectConfigOdoo odoo;

    VirtualEnv _venv;

    /** Initialize with automatic config discovery
      *
      **/
    static auto loadProject() {
        auto s_config_path = Path.current.searchFileUp("odood.yml");
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
            in ProjectConfigOdoo odoo) {

        this.project_root = project_root.expandTilde.toAbsolute;
        this.directories = directories;
        this.odoo = odoo;

        this._venv = VirtualEnv(
            this.project_root.join("venv"),
            guessPySerie(odoo.serie));
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
        auto root = project_root.expandTilde.toAbsolute;
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
             "https://github.com/odoo/odoo");
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
    @property const (Path) config_path() const { return _config_path.get; }

    /// LOdoo instance for this project
    @property const(LOdoo) lodoo() const {
        return LOdoo(this, this.odoo.configfile);
    }

    /** VirtualEnv related to this project.
      * Allows to run commands in convext of virtual environment,
      * install packages, etc
      **/
    @property auto venv() const {
        return _venv;
    }

    /** OdooServer wrapper to manage server of this Odood project
      * Provides basic methods to start/stop/etc odoo server.
      **/
    @property auto server() const {
        return OdooServer(this);
    }

    /** AddonManager related to this project
      * Allows to manage addons of this project
      **/
    @property auto addons() const {
        return AddonManager(this);
    }

    /** Create new test-runner instance.
      **/
    @property auto testRunner() const {
        return OdooTestRunner(this);
    }

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

        this.initializeProjectDirs();
        this.installDownloadOdoo();
        this.installVirtualenv(python_version, node_version);
        this.installOdoo();
        this.installOdooConfig(odoo_config);
    }

    /// ditto
    void initialize() {
        auto odoo_config = this.initOdooConfig();
        initialize(odoo_config);
    }

    /// Get configuration for Odoo
    auto getOdooConfig() {
        return this.readOdooConfig;
    }

    /// Add new repo to project
    deprecated void addRepo(in string url, in string branch) {
        this.addons.addRepo(url, branch);
    }
}

