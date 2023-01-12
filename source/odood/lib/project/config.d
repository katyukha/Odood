/// This module handles config of instance managed by odood
module odood.lib.project.config;

private import thepath: Path;
private static import dyaml;
private static import dyaml.dumper;
private static import dyaml.style;

private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.python: guessPySerie;
private import odood.lib.venv: VirtualEnv;
private import odood.lib.server: OdooServer;

/** Struct that represents odoo-specific configuration
  **/
private struct ProjectConfigOdoo {
    /// Main odoo config file
    Path configfile;

    /// Path to log file
    Path logfile;

    /// Path to odoo installation
    Path path;

    /// Path to PID file, that will store process ID of running odoo server
    Path pidfile;

    /// Version of odoo installed
    OdooSerie serie;

    /// The branch of odoo that installed. By default same as odoo_serie.
    string branch;

    /// Repo, odoo is installed from.
    string repo;

    this(in Path project_root,
            in ProjectConfigDirectories directories,
            in OdooSerie odoo_serie,
            in string odoo_branch, in string odoo_repo) {

        configfile = directories.conf.join("odoo.conf");
        logfile = directories.log.join("odoo.log");
        pidfile = project_root.join("odoo.pid");
        path = project_root.join("odoo");
        serie = odoo_serie;
        branch = odoo_branch;
        repo = odoo_repo;
    }

    this(in ref dyaml.Node config) {
        this.configfile = config["configfile"].as!string;
        this.logfile = config["logfile"].as!string;
        this.pidfile = config["pidfile"].as!string;
        this.path = Path(config["path"].as!string);
        this.serie = OdooSerie(config["version"].as!string);
        this.branch = config["branch"].as!string;
        this.repo = config["repo"].as!string;
    }

    dyaml.Node toYAML() const {
        return dyaml.Node([
            "version": this.serie.toString,
            "branch": this.branch,
            "repo": this.repo,
            "path": this.path.toString,
            "configfile": this.configfile.toString,
            "logfile": this.logfile.toString,
            "pidfile": this.pidfile.toString,
        ]);
    }
}


/** Stuct that represents directory structure for the project
  **/
private struct ProjectConfigDirectories {

    /// Directory to store odoo configurations
    Path conf;

    /// Directory to store logs
    Path log;

    /// Directory to store downloads (downloaded apps, etc)
    Path downloads;

    /// Directory for custom addons, managed by odood
    Path addons;

    /// Directory for odoo data-files
    Path data;

    /// Backups dir, that will be used to store backups made by odood
    Path backups;

    /// Repositories directory, that will be used to keep
    /// fetched git repositories
    Path repositories;

    this(in Path root) {
        this.conf = root.join("conf");
        this.log = root.join("logs");
        this.downloads = root.join("downloads");
        this.addons = root.join("custom_addons");
        this.data = root.join("data");
        this.backups = root.join("backups");
        this.repositories = root.join("repositories");
    }

    this(in ref dyaml.Node config) {
        this.conf = Path(config["conf"].as!string);
        this.log = Path(config["log"].as!string);
        this.downloads = Path(config["downloads"].as!string);
        this.addons = Path(config["addons"].as!string);
        this.data = Path(config["data"].as!string);
        this.backups = Path(config["backups"].as!string);
        this.repositories = Path(config["repositories"].as!string);
    }

    dyaml.Node toYAML() const {
        import dyaml: Node;
        return Node([
            "conf": this.conf.toString,
            "log": this.log.toString,
            "downloads": this.downloads.toString,
            "addons": this.addons.toString,
            "data": this.data.toString,
            "backups": this.backups.toString,
            "repositories": this.repositories.toString,
        ]);
    }
}


/** Project configuration
  **/
final class ProjectConfig {

    /// Root project directory
    Path project_root;

    ProjectConfigDirectories directories;

    ProjectConfigOdoo odoo;

    VirtualEnv _venv;

    // TODO: Add validation of config


    /** Create new config from basic parameters.
      *
      * Params:
      *     root_path = Path to the project root directory
      *     odoo_serie = Version of Odoo to run
      *     odoo_branch = Name of the branch to get Odoo from
      *     odoo_repo = URL to the repository to get Odoo from
      **/
    this(in Path root_path, in OdooSerie odoo_serie,
            in string odoo_branch, in string odoo_repo) {
        this.project_root = root_path.expandTilde.toAbsolute;
        this.directories = ProjectConfigDirectories(this.project_root);
        this.odoo = ProjectConfigOdoo(
            this.project_root,
            this.directories,
            odoo_serie,
            odoo_branch,
            odoo_repo);

        this._venv = VirtualEnv(
            this.project_root.join("venv"),
            guessPySerie(odoo_serie));
    }

    /// ditto
    this(in Path root_path, in OdooSerie odoo_serie) {
        this(root_path,
             odoo_serie,
             odoo_serie.toString, 
             "https://github.com/odoo/odoo");
    }

    /** Create this config instance from YAML node
      *
      * Params:
      *     node = YAML node representation to initialize config from
      **/
    this(in ref dyaml.Node config) {
        this.project_root = Path(config["project_root"].as!string);
        this.directories = ProjectConfigDirectories(config["directories"]);
        this.odoo = ProjectConfigOdoo(config["odoo"]);

        this._venv = VirtualEnv(config["virtualenv"]);
    }

    /** VirtualEnv related to this project config.
      * Allows to run commands in context of virtual environment
      **/
    @property VirtualEnv venv() const {
        return _venv;
    }

    /** OdooServer wrapper for this project config.
      * Allows to manage odoo server.
      **/
    @property OdooServer server() const {
        return OdooServer(this);
    }

    /** Serialize config to YAML node
      **/
    dyaml.Node toYAML() const {
        import dyaml: Node;
        return Node([
            "project_root": Node(this.project_root.toString),
            "odoo": this.odoo.toYAML(),
            "directories": this.directories.toYAML(),
            "virtualenv": _venv.toYAML(),
        ]);
    }

    void save(in Path path) const {
        auto dumper = dyaml.dumper.dumper();
        dumper.defaultCollectionStyle = dyaml.style.CollectionStyle.block;

        auto out_file = path.openFile("w");
        scope (exit) {
            out_file.close();
        }
        dumper.dump(out_file.lockingTextWriter, this.toYAML);
    }

}

