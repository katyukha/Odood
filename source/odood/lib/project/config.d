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


/** Project configuration
  **/
struct ProjectConfig {

    /// Root project directory
    Path project_root;

    /// Directory to store odoo configurations
    Path conf_dir;

    /// Main odoo config file
    Path odoo_conf;

    /// Directory to store logs
    Path log_dir;

    /// Path to log file
    Path log_file;

    /// Directory to store downloads (downloaded apps, etc)
    Path downloads_dir;

    /// Directory for custom addons, managed by odood
    Path addons_dir;

    /// Directory for odoo data-files
    Path data_dir;

    /// Path to odoo installation
    Path odoo_path;

    /// Path to PID file, that will store process ID of running odoo server
    Path odoo_pid_file;

    /// Backups dir, that will be used to store backups made by odood
    Path backups_dir;

    /// Repositories directory, that will be used to keep
    /// fetched git repositories
    Path repositories_dir;

    /// Version of odoo installed
    OdooSerie odoo_serie;

    /// The branch of odoo that installed. By default same as odoo_serie.
    string odoo_branch;

    /// Repo, odoo is installed from.
    string odoo_repo;

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
        this.conf_dir = this.project_root.join("conf");
        this.log_dir = this.project_root.join("logs");
        this.downloads_dir = this.project_root.join("downloads");
        this.addons_dir = this.project_root.join("custom_addons");
        this.data_dir = this.project_root.join("data");
        this.backups_dir = this.project_root.join("backups");
        this.repositories_dir = this.project_root.join("repositories");

        this.odoo_conf = this.conf_dir.join("odoo.conf");
        this.log_file = this.log_dir.join("odoo.log");
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
        this.conf_dir = Path(config["directories"]["conf"].as!string);
        this.log_dir = Path(config["directories"]["log"].as!string);
        this.downloads_dir = Path(
            config["directories"]["downloads"].as!string);
        this.addons_dir = Path(config["directories"]["addons"].as!string);
        this.data_dir = Path(config["directories"]["data"].as!string);
        this.backups_dir = Path(config["directories"]["backups"].as!string);
        this.repositories_dir = Path(
            config["directories"]["repositories"].as!string);

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
            "directories": Node([
                "conf": this.conf_dir.toString,
                "log": this.log_dir.toString,
                "downloads": this.downloads_dir.toString,
                "addons": this.addons_dir.toString,
                "data": this.data_dir.toString,
                "backups": this.backups_dir.toString,
                "repositories": this.repositories_dir.toString,
            ]),
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

