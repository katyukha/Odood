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

    dyaml.Node toYAML() {
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
struct ProjectConfig {

    /// Root project directory
    Path project_root;

    /// Main odoo config file
    Path odoo_conf;

    /// Path to log file
    Path log_file;

    /// Path to odoo installation
    Path odoo_path;

    /// Path to PID file, that will store process ID of running odoo server
    Path odoo_pid_file;

    /// Version of odoo installed
    OdooSerie odoo_serie;

    /// The branch of odoo that installed. By default same as odoo_serie.
    string odoo_branch;

    /// Repo, odoo is installed from.
    string odoo_repo;

    ProjectConfigDirectories directories;

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

        this.odoo_conf = this.directories.conf.join("odoo.conf");
        this.log_file = this.directories.log.join("odoo.log");
        this.odoo_pid_file = this.project_root.join("odoo.pid");
        this.odoo_path = this.project_root.join("odoo");
        this.odoo_serie = odoo_serie;
        this.odoo_branch = odoo_branch;
        this.odoo_repo = odoo_repo;

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

        if (config["odoo"].containsKey("configfile"))
            this.odoo_conf = config["odoo"]["configfile"].as!string;
        else
            this.odoo_conf = Path(config["files"]["odoo_config"].as!string);

        if (config["odoo"].containsKey("logfile"))
            this.log_file = config["odoo"]["logfile"].as!string;
        else
            this.log_file = Path(config["files"]["odoo_log"].as!string);

        if (config["odoo"].containsKey("pidfile"))
            this.odoo_pid_file = config["odoo"]["pidfile"].as!string;
        else
            this.odoo_pid_file = Path(config["files"]["odoo_pid"].as!string);

        this.odoo_path = Path(config["odoo"]["path"].as!string);
        this.odoo_serie = OdooSerie(config["odoo"]["version"].as!string);
        this.odoo_branch = config["odoo"]["branch"].as!string;
        this.odoo_repo = config["odoo"]["repo"].as!string;

        if (config.containsKey("virtualenv")) {
            this._venv = VirtualEnv(config["virtualenv"]);
        } else {
            this._venv = VirtualEnv(
                Path(config["directories"]["venv"].as!string),
                guessPySerie(odoo_serie),
            );
        }
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
    dyaml.Node toYAML() {
        import dyaml: Node;
        return Node([
            "project_root": Node(this.project_root.toString),
            "odoo": Node([
                "version": this.odoo_serie.toString,
                "branch": this.odoo_branch,
                "repo": this.odoo_repo,
                "path": this.odoo_path.toString,
                "configfile": this.odoo_conf.toString,
                "logfile": this.log_file.toString,
                "pidfile": this.odoo_pid_file.toString,
            ]),
            "directories": this.directories.toYAML(),
            "virtualenv": _venv.toYAML(),
        ]);
    }

    void save(in Path path) {
        auto dumper = dyaml.dumper.dumper();
        dumper.defaultCollectionStyle = dyaml.style.CollectionStyle.block;

        auto out_file = path.openFile("w");
        scope (exit) {
            out_file.close();
        }
        dumper.dump(out_file.lockingTextWriter, this.toYAML);
    }

}

