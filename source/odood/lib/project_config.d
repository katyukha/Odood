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


    this(in Path root_path, in OdooSerie odoo_serie,
            in string odoo_branch, in string odoo_repo) {
        this.root_dir = root_path.expandTilde.toAbsolute;
        this.conf_dir = this.root_dir.join("conf");
        this.odoo_conf = this.conf_dir.join("odoo.conf");
        this.odoo_test_conf = this.conf_dir.join("odoo.test.conf");
        this.log_dir = this.root_dir.join("logs");
        this.log_file = this.log_dir.join("odoo.log");
        this.downloads_dir = this.root_dir.join("downloads");
        this.addons_dir = this.root_dir.join("custom_addons");
        this.data_dir = this.root_dir.join("data");
        this.venv_dir = this.root_dir.join("venv");
        this.odoo_pid_file = this.root_dir.join("odoo.pid");
        this.backups_dir = this.root_dir.join("backups");
        this.repositories_dir = this.root_dir.join("repositories");
        this.odoo_serie = odoo_serie;
        this.odoo_branch = odoo_branch;
        this.odoo_repo = odoo_repo;
    }


    this(in Path root_path, in OdooSerie odoo_serie) {
        this(root_path, odoo_serie, odoo_serie.toString, 
             "https://github.com/odoo/odoo");
    }

    this(in ref dyaml.Node config) {
        this.fromYAML(config);
    }

    void fromYAML(in ref dyaml.Node config) {
        this.root_dir = Path(config["root_dir"].as!string);
        this.conf_dir = Path(config["conf_dir"].as!string);
        this.odoo_conf = Path(config["odoo_conf"].as!string);
        this.odoo_test_conf = Path(config["odoo_test_conf"].as!string);
        this.log_dir = Path(config["log_dir"].as!string);
        this.log_file = Path(config["log_file"].as!string);
        this.downloads_dir = Path(config["downloads_dir"].as!string);
        this.addons_dir = Path(config["addons_dir"].as!string);
        this.data_dir = Path(config["data_dir"].as!string);
        this.venv_dir = Path(config["venv_dir"].as!string);
        this.odoo_path = Path(config["odoo_path"].as!string);
        this.odoo_pid_file = Path(config["odoo_pid_file"].as!string);
        this.backups_dir = Path(config["backups_dir"].as!string);
        this.repositories_dir = Path(config["repositories_dir"].as!string);
        this.odoo_serie = OdooSerie(config["odoo_serie"].as!string);
        this.odoo_branch = config["odoo_branch"].as!string;
        this.odoo_repo = config["odoo_repo"].as!string;
    }


    dyaml.Node toYAML() {
        return dyaml.Node([
            "root_dir": this.root_dir.toString,
            "conf_dir": this.conf_dir.toString,
            "odoo_conf": this.odoo_conf.toString,
            "odoo_test_conf": this.odoo_test_conf.toString,
            "log_dir": this.log_dir.toString,
            "log_file": this.log_file.toString,
            "downloads_dir": this.downloads_dir.toString,
            "addons_dir": this.addons_dir.toString,
            "data_dir": this.data_dir.toString,
            "venv_dir": this.venv_dir.toString,
            "odoo_path": this.odoo_path.toString,
            "odoo_pid_file": this.odoo_pid_file.toString,
            "backups_dir": this.backups_dir.toString,
            "repositories_dir": this.repositories_dir.toString,
            "odoo_serie": this.odoo_serie.toString,
            "odoo_branch": this.odoo_branch,
            "odoo_repo": this.odoo_repo,
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

