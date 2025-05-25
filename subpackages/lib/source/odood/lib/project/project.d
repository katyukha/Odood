module odood.lib.project.project;

private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable, nullable;
private import std.logger;
private import std.conv: to, ConvException;
private import std.datetime.systime: Clock;

private import thepath: Path;
private import theprocess: Process;
private import dini: Ini;
private import dyaml;
private import zipper: Zipper, ZipMode;

private import odood.exception: OdoodException;

private import odood.lib.odoo.config: initOdooConfig, readOdooConfig;
private import odood.lib.odoo.python: guessPySerie, guessVenvOptions;
private import odood.lib.odoo.lodoo: LOdoo;
private import odood.lib.server: OdooServer;
private import odood.lib.venv: VirtualEnv, VenvOptions;
private import odood.lib.addons.manager: AddonManager;
private import odood.lib.odoo.test: OdooTestRunner;
private import odood.lib.odoo.db_manager: OdooDatabaseManager;
public import odood.lib.project.config:
    ProjectConfigOdoo, ProjectConfigDirectories, DEFAULT_ODOO_REPO;

private import odood.utils.odoo.serie: OdooSerie;
private import odood.git: isGitRepo, GitRepository, GitURL;
private import odood.utils: generateRandomString;
private import odood.lib.assembly: Assembly, AssemblySpec;


/** Defined the way to install Odoo: from archive or from git
  **/
enum OdooInstallType {
    Archive,
    Git,
}

/* TODO: We have to implement project-type MonoRepo
 *
 * There could be two types of projects:
 * - Assembly (Mono Repo)
 * - MultiRepo
 *
 * Assembly is desired type for production server installations
 * MultiRepo is usually good for development and flexibility.
 *
 * The only difference between these types is that assmbly take all addons from single repository,
 * while multirepo (current behavior) take addons from all repos.
 *
 * For this reason: we have to add new direcotry 'assembly' inside project,
 * that should contain assembly repostitory.
 * When project is switched to Assembly type, then all addons that are not
 * from assembly, must be cleaned from custom addons.
 * Instead all addons from assembly should be linked to custom addons.
 *
 * Also, we have to develop some kind of spec, that will allow to automatically
 * populate assembly with desired addons from various sources (git repos, addon market, etc).
 *
 */

/** Define path for odood system-wide project config
  **/
immutable auto ODOOD_SYSTEM_CONFIG_PATH = Path("/", "etc", "odood.yml");

/** The Odood project.
  * The main entity to manage whole Odood project
  **/
class Project {
    //private const ProjectConfig _config;
    private Nullable!Path _config_path;

    /// Root project directory
    private Path _project_root;

    private ProjectConfigDirectories _directories;

    private ProjectConfigOdoo _odoo;

    private VirtualEnv _venv;

    private Nullable!Assembly _assembly;

    /** Try to load project config automaticall. Returns nullable.
      *
      * Returns:
      *     Nullable!Project with value set if project loaded successfully and null otherwise.
      **/
    static Nullable!Project maybeLoadProject() {
        auto s_config_path = Path.current.searchFileUp("odood.yml");

        // If config is not found in current directory and above,
        // check server-wide config (may be it is installed in server-mode)
        if (s_config_path.isNull && ODOOD_SYSTEM_CONFIG_PATH.exists)
            // We have to copy Path, because nullable does not work on immutable path.
            s_config_path = Path(ODOOD_SYSTEM_CONFIG_PATH.toString).nullable;

        if (s_config_path.isNull)
            return Nullable!Project.init;
        return maybeLoadProject(s_config_path.get);
    }

    /** Try to load project from path. Automatically discover odood.yml configuration
      * file and load it.
      *
      * Params:
      *     path = is path to odood config file or path to directory
      *         that contains odood.yml config file
      * Returns:
      *     Nullable!Project with value set if project loaded successfully and null otherwise.
      **/
    static Nullable!Project maybeLoadProject(in Path path) {
        if (path.exists && path.isFile) {
            Node config = dyaml.Loader.fromFile(path.toString()).load();
            return (new Project(config, path)).nullable;
        } else if (path.exists && path.isDir && path.join("odood.yml").exists) {
            auto load_path = path.join("odood.yml");
            Node config = dyaml.Loader.fromFile(load_path.toString()).load();
            return (new Project(config, load_path)).nullable;
        }
        return Nullable!Project.init;
    }

    /** Initialize with automatic config discovery
      *
      **/
    static auto loadProject() {
        auto res = maybeLoadProject;

        enforce!OdoodException(
            !res.isNull,
            "Cannot find and load OdooD configuration file!");
        return res.get;
    }

    /** Load project from path. Automatically discover odood.yml configuration
      * file and load it.
      *
      * Params:
      *     path = is path to odood config file or path to directory
      *         that contains odood.yml config file
      **/
    static auto loadProject(in Path path) {
        auto res = maybeLoadProject(path);

        enforce!OdoodException(
            !res.isNull,
            "Cannot find and load OdooD configuration file!");
        return res.get;
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
            in VirtualEnv venv,
            in Nullable!Assembly assembly=Nullable!Assembly.init) {
        this._project_root = project_root.toAbsolute;
        this._directories = directories;
        this._odoo = odoo;
        this._venv = venv;
        this._assembly = cast(Nullable!Assembly) assembly;
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
            VirtualEnv(
                project_root.join("venv"),
                guessPySerie(odoo.serie))
        );
    }

    /// ditto
    this(in Node yaml_config) {
        if (yaml_config.containsKey("assembly-path"))
            this(
                Path(yaml_config["project_root"].as!string),
                ProjectConfigDirectories(
                    Path(yaml_config["project_root"].as!string),
                    yaml_config["directories"]),
                ProjectConfigOdoo(yaml_config["odoo"]),
                VirtualEnv(yaml_config["virtualenv"]),
                Assembly.maybeLoad(this, Path(yaml_config["assembly-path"].as!string)),
            );
        else
            this(
                Path(yaml_config["project_root"].as!string),
                ProjectConfigDirectories(
                    Path(yaml_config["project_root"].as!string),
                    yaml_config["directories"]),
                ProjectConfigOdoo(yaml_config["odoo"]),
                VirtualEnv(yaml_config["virtualenv"]),
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

    /** Assembly related to this project.
      **/
    Nullable!Assembly assembly() const { return cast(Nullable!Assembly)_assembly; }

    /** String representation of Odood project
      **/
    override string toString() const {
        return "Odood project (odoo: %s, py: %s) at %s".format(
            _odoo.serie, _venv.py_version, _project_root);
    }

    /** psql process prepared and configured to run
      *
      * This method could be used to get prepared psql command
      * with already configured params for connection to database
      *
      * Returns: Process instance (from theprocess package)
      **/
    auto psql() const {
        auto odoo_conf = getOdooConfig();

        // TODO: Use resolveProgramPath here
        auto res = Process("psql")
            .withEnv(
                "PGUSER",
                odoo_conf["options"].hasKey("db_user") ?
                    odoo_conf["options"].getKey("db_user") : "odoo")
            .withEnv(
                "PGPASSWORD",
                odoo_conf["options"].hasKey("db_password") ?
                    odoo_conf["options"].getKey("db_password") : "odoo");

        if (odoo_conf["options"].hasKey("db_host"))
            res.setEnv(
                "PGHOST", odoo_conf["options"].getKey("db_host"));
        if (odoo_conf["options"].hasKey("db_port")) {
            auto db_port = odoo_conf["options"].getKey("db_port");
            try {
                res.setEnv("PGPORT", db_port.to!(int).to!string);
            } catch (ConvException) {
                warningf("Unparsable value for db port: %s", db_port);
            }
        }
        return res;
    }

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

        if (!_assembly.isNull)
            yaml_data["assembly-path"] = _assembly.get.path.toString;

        infof("Saving Odood config...");
        dumper.dump(out_file.lockingTextWriter, yaml_data);
        infof("Odood config saved at %s", path);
    }

    /** Save project configuration to default config file.
      **/
    void save() {
        if (_config_path.isNull)
            save(project_root.join("odood.yml"));
        else
            save(config_path);
    }

    /** Return installation type of Odoo in this project.
      * Odoo could be installed from archive, that is default and requires
      * small amount of data to be downloaded on installation.
      * Or, it could be installed as git repo with history. This type of
      * installation mostly interested for developers, whow want to push
      * some pull requests to Odoo repo.
      **/
    OdooInstallType odoo_install_type() const {
        if (this.odoo.path.join(".git").exists)
            return OdooInstallType.Git;
        return OdooInstallType.Archive;
    }

    /** Initialize project.
      * This will create new project directory and install Odoo there.
      *
      * Params:
      *     odoo_config: INI struct, that represents configuration for Odoo
      **/
    void initialize(ref Ini odoo_config,
            in VenvOptions venv_options,
            in OdooInstallType install_type=OdooInstallType.Archive) {
        import odood.lib.install;

        // Initialize project directories
        this.project_root.mkdir(true);
        this.directories.initializeDirecotires();

        // Initialize project (install everything needed)
        // TODO: parallelize download of Odoo and installation of virtualenv
        with(OdooInstallType) final switch(install_type) {
            case Archive:
                this.installDownloadOdoo();
                break;
            case Git:
                this.installCloneGitOdoo();
                break;
        }
        this.installVirtualenv(venv_options);
        this.installOdoo();
        this.installOdooConfig(odoo_config);
        // TODO: Automatically save config
    }

    /// ditto
    void initialize() {
        auto odoo_config = this.initOdooConfig;
        auto venv_options = this.odoo.serie.guessVenvOptions;
        initialize(odoo_config, venv_options);
    }

    /** Initialize assembly for this project
      **/
    void initializeAssembly() {
        _project_root.join("assembly").mkdir(true);
        _assembly = Assembly.initialize(
            project: this,
            path: _project_root.join("assembly")).nullable;
        save();
    }

    void initializeAssembly(in GitURL git_url) {
        _project_root.join("assembly").mkdir(true);
        _assembly = Assembly.initialize(
            project: this,
            path: _project_root.join("assembly"),
            git_url: git_url).nullable;
        save();
    }

    /** Backup odoo sources located at this.odoo.path.
      **/
    private Path backupOdooSource() {
        // Archive current odoo source code
        auto backup_path = this.directories.backups.join(
            "odoo-%s-%s-%s.zip".format(
                this.odoo.serie,
                "%s-%s-%s".format(
                    Clock.currTime.year,
                    Clock.currTime.month,
                    Clock.currTime.day),
                generateRandomString(4)
            )
        );
        infof("Saving backup of Odoo sources to %s...", backup_path);
        Zipper(
            backup_path,
            ZipMode.CREATE,
        ).add(this.odoo.path);
        return backup_path;
    }

    /** Update odoo to newer version
      *
      * Params:
      *     backup = if set to true, then system will take backup of Odoo,
      *         before update.
      **/
    void updateOdoo(in bool backup=false) {
        import odood.lib.install;

        with(OdooInstallType) final switch(this.odoo_install_type) {
            case Archive:
                if (this.odoo.path.exists()) {
                    if (backup)
                        backupOdooSource();
                    infof("Removing odoo installation at %s", this.odoo.path);
                    this.odoo.path.remove();
                }

                this.installDownloadOdoo();
                break;
            case Git:

                auto dt_string = Clock.currTime.toISOString;
                auto tag_name = "%s-before-update-%s".format(
                    this.odoo.serie, dt_string);

                auto repo = new GitRepository(this.odoo.path);
                repo.setTag(
                    tag_name,
                    "Save before odoo update (%s)".format(dt_string));
                repo.pull();

                break;
        }
        this.installOdoo();
        infof("Odoo update completed.");
    }

    /** Reinstall odoo to different Odoo version
      *
      * Note, that this operation is dangerous, do it on your own risk.
      *
      * Params:
      *     serie = Odoo version to install
      *     backup = if set to true, then system will take backup of Odoo,
      *         before update. Default is true.
      **/
    void reinstallOdoo(
            in OdooSerie serie,
            in OdooInstallType install_type,
            in VenvOptions venv_options,
            in bool backup=true)
    in(serie.isValid)
    do {
        import odood.lib.install;

        auto origin_serie = this.odoo.serie;

        if (this.odoo.path.exists()) {
            if (backup)
                backupOdooSource();
            infof("Removing odoo installation at %s", this.odoo.path);
            this.odoo.path.remove();
        }

        if (this.venv.path.exists()) {
            this.venv.path.remove();
        }

        this._odoo.serie = serie;
        this._odoo.branch = serie.toString;

        this.installVirtualenv(venv_options);

        with(OdooInstallType) final switch(install_type) {
            case Archive:
                this.installDownloadOdoo();
                break;
            case Git:
                this.installCloneGitOdoo();
                break;
        }
        this.installOdoo();

        // TODO: Take care on repostitories and custom addons.
        // TODO: Revert changes on failure when possible

        this.save();
        infof(
            "Odoo successfully reinstalled from %s to %s version.",
            origin_serie, this.odoo.serie);
    }

    /// ditto
    void reinstallOdoo(
            in OdooSerie serie,
            in bool backup=true) {
        this.reinstallOdoo(
            serie,
            this.odoo_install_type,
            serie.guessVenvOptions,
            backup);
    }

    /// Get configuration for Odoo
    auto getOdooConfig() const {
        return this.readOdooConfig;
    }
}
