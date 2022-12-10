/// This module handles config of instance managed by odood
module odood.lib.project_config;

private import thepath: Path;
private import odood.lib.odoo_serie: OdooSerie;
private static import dyaml;
private static import dyaml.dumper;
private static import dyaml.style;


struct ProjectConfig {

    /// Root project directory
    Path root_dir;

    /// Directory to store executables
    Path bin_dir;

    /// Directory to store odoo configurations
    Path conf_dir;

    /// Main odoo config file
    Path odoo_conf;

    /// Odoo configuration file for tests
    Path odoo_test_conf;

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

    /// Virtual environment directory
    Path venv_dir;

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

    /// Version of nodejs to install. Default: lts
    string node_version = "lts";

    /** Version of python to install.
      * if null, then Odoo will automatically detect if specific version of
      * python have to be built, or use system python.
      * Must be string in format "X.Y.Z". For example '3.9.12'.
      **/
    string python_version = null;

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
        this.root_dir = root_path.expandTilde.toAbsolute;
        this.bin_dir = this.root_dir.join("bin");
        this.conf_dir = this.root_dir.join("conf");
        this.log_dir = this.root_dir.join("logs");
        this.downloads_dir = this.root_dir.join("downloads");
        this.addons_dir = this.root_dir.join("custom_addons");
        this.data_dir = this.root_dir.join("data");
        this.venv_dir = this.root_dir.join("venv");
        this.backups_dir = this.root_dir.join("backups");
        this.repositories_dir = this.root_dir.join("repositories");

        this.odoo_conf = this.conf_dir.join("odoo.conf");
        this.odoo_test_conf = this.conf_dir.join("odoo.test.conf");
        this.log_file = this.log_dir.join("odoo.log");
        this.odoo_pid_file = this.root_dir.join("odoo.pid");

        this.odoo_path = this.root_dir.join("odoo");
        this.odoo_serie = odoo_serie;
        this.odoo_branch = odoo_branch;
        this.odoo_repo = odoo_repo;
    }

    /// ditto
    this(in Path root_path, in OdooSerie odoo_serie) {
        this(root_path, odoo_serie, odoo_serie.toString, 
             "https://github.com/odoo/odoo");
    }

    /** Create this config instance from YAML node
      *
      * Params:
      *     node = YAML node representation to initialize config from
      **/
    this(in ref dyaml.Node node) {
        this.fromYAML(node);
    }

    /** Parse YAML representation of config, and initialize this instance.
      *
      * Params:
      *     config = YAML node representation to initialize config from
      **/
    void fromYAML(in ref dyaml.Node config) {
        this.root_dir = Path(config["directories"]["root_dir"].as!string);
        this.bin_dir = Path(config["directories"]["bin_dir"].as!string);
        this.conf_dir = Path(config["directories"]["conf_dir"].as!string);
        this.log_dir = Path(config["directories"]["log_dir"].as!string);
        this.downloads_dir = Path(
            config["directories"]["downloads_dir"].as!string);
        this.addons_dir = Path(config["directories"]["addons_dir"].as!string);
        this.data_dir = Path(config["directories"]["data_dir"].as!string);
        this.venv_dir = Path(config["directories"]["venv_dir"].as!string);
        this.backups_dir = Path(config["directories"]["backups_dir"].as!string);
        this.repositories_dir = Path(
            config["directories"]["repositories_dir"].as!string);

        this.odoo_conf = Path(config["files"]["odoo_config"].as!string);
        this.odoo_test_conf = Path(config["files"]["odoo_test_config"].as!string);
        this.log_file = Path(config["files"]["odoo_log"].as!string);
        this.odoo_pid_file = Path(config["files"]["odoo_pid"].as!string);

        this.odoo_path = Path(config["odoo"]["path"].as!string);
        this.odoo_serie = OdooSerie(config["odoo"]["version"].as!string);
        this.odoo_branch = config["odoo"]["branch"].as!string;
        this.odoo_repo = config["odoo"]["repo"].as!string;

        this.node_version = config["nodejs"]["version"].as!string;
        this.python_version = config["python"]["version"].as!string;
    }

    /** Serialize config to YAML node
      **/
    dyaml.Node toYAML() {
        import dyaml: Node;
        return Node([
            "odoo": Node([
                "version": this.odoo_serie.toString,
                "branch": this.odoo_branch,
                "repo": this.odoo_repo,
                "path": this.odoo_path.toString,
            ]),
            "directories": Node([
                "root_dir": this.root_dir.toString,
                "bin_dir": this.bin_dir.toString,
                "conf_dir": this.conf_dir.toString,
                "log_dir": this.log_dir.toString,
                "downloads_dir": this.downloads_dir.toString,
                "addons_dir": this.addons_dir.toString,
                "data_dir": this.data_dir.toString,
                "venv_dir": this.venv_dir.toString,
                "backups_dir": this.backups_dir.toString,
                "repositories_dir": this.repositories_dir.toString,
            ]),
            "files": Node([
                "odoo_config": this.odoo_conf.toString,
                "odoo_test_config": this.odoo_test_conf.toString,
                "odoo_log": this.log_file.toString,
                "odoo_pid": this.odoo_pid_file.toString,
            ]),
            "nodejs": Node([
                "version": this.node_version,
            ]),
            "python": Node([
                "version": this.python_version,
            ]),
        ]);
    }

    void load(in Path path) {
        dyaml.Node root = dyaml.Loader.fromFile(path.toString()).load();
        this.fromYAML(root);
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

