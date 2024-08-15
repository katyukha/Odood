/// This module handles config of instance managed by odood
module odood.lib.project.config;

private import std.format: format;

private import thepath: Path;
private static import dyaml;

private import odood.utils.odoo.serie: OdooSerie;

package(odood)
    immutable string DEFAULT_ODOO_REPO="https://github.com/odoo/odoo";

/** This enum describes what tool is used to run and manage Odoo in background
  **/
enum ProjectServerSupervisor {
    /// Server is managed by Odood.
    Odood,

    /// Server is managed by init script in /etc/init.d odoo
    InitScript,
}


/** Struct that represents odoo-specific configuration
  **/
struct ProjectConfigOdoo {
    /// Main odoo config file
    Path configfile;

    /** Odoo configuration file, that have to be used to run tests.
      * It is required to have separate config file, because older versions
      * of odoo do not support overwriting config file options
      * via CLI arguments.
      **/
    Path testconfigfile;

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

    /// Name of the user that have to run Odoo
    string server_user;

    /// Managed by OS.
    ProjectServerSupervisor server_supervisor = ProjectServerSupervisor.Odood;

    /// Path to init script, of project's server is managed by init script.
    Path server_init_script_path;

    this(in Path project_root,
            in ProjectConfigDirectories directories,
            in OdooSerie odoo_serie,
            in string odoo_branch,
            in string odoo_repo) {

        import std.string: empty;

        configfile = directories.conf.join("odoo.conf");
        testconfigfile = directories.conf.join("odoo.test.conf");
        logfile = directories.log.join("odoo.log");
        pidfile = project_root.join("odoo.pid");
        path = project_root.join("odoo");
        serie = odoo_serie;
        branch = odoo_branch.empty ? odoo_serie.toString : odoo_branch;
        repo = odoo_repo.empty ? DEFAULT_ODOO_REPO : odoo_repo;
    }

    this(in dyaml.Node config) {
        /* TODO: think about following structure of test config in yml:
         * odoo:
         *     configfile: some/path,
         *     logfile: some/path,
         *     test:
         *         enable: true
         *         configfile: some/path
         **/
        this.configfile = config["configfile"].as!string;
        this.testconfigfile = config["testconfigfile"].as!string;
        this.logfile = config["logfile"].as!string;
        this.pidfile = config["pidfile"].as!string;
        this.path = Path(config["path"].as!string);
        this.serie = OdooSerie(config["version"].as!string);
        this.branch = config["branch"].as!string;
        if (config["repo"].as!string.length > 0)
            this.repo = config["repo"].as!string;
        else
            this.repo = "https://github.com/odoo/odoo";

        // TODO: Think about moving server configuration to separate section
        //       in yaml.
        // TODO: introduce config versions and automatic migration of config files.
        if (config.containsKey("server-user"))
            this.server_user = config["server-user"].as!string;
        if (config.containsKey("server-supervisor"))
            switch (config["server-supervisor"].as!string) {
                case "odood":
                    this.server_supervisor = ProjectServerSupervisor.Odood;
                    break;
                case "init-script":
                    this.server_supervisor = ProjectServerSupervisor.InitScript;
                    break;
                default:
                    assert(
                        0,
                        "Server supervisor type %s is not supported!".format(
                            config["server-supervisor"].as!string));
            }
        else
            this.server_supervisor = ProjectServerSupervisor.Odood;
    }

    dyaml.Node toYAML() const {
        auto result = dyaml.Node([
            "version": this.serie.toString,
            "branch": this.branch,
            "repo": this.repo,
            "path": this.path.toString,
            "configfile": this.configfile.toString,
            "testconfigfile": this.testconfigfile.toString,
            "logfile": this.logfile.toString,
            "pidfile": this.pidfile.toString,
        ]);
        if (this.server_user)
            result["server-user"] = this.server_user;

        /// Serialize supervisor used for this project
        final switch(this.server_supervisor) {
            case ProjectServerSupervisor.Odood:
                result["server-supervisor"] = "odood";
                break;
            case ProjectServerSupervisor.InitScript:
                result["server-supervisor"] = "init-script";
                break;
        }

        return result;
    }
}


/** Stuct that represents directory structure for the project
  **/
struct ProjectConfigDirectories {

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

    this(in dyaml.Node config) {
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

    /** Initialize project directory structure.
        This function will create all needed directories for project.
     **/
    package void initializeDirecotires() const {
        this.conf.mkdir(true);
        this.log.mkdir(true);
        this.downloads.mkdir(true);
        this.addons.mkdir(true);
        this.data.mkdir(true);
        this.backups.mkdir(true);
        this.repositories.mkdir(true);
    }

}
