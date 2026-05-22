module odood.cli.commands.init;

private import std.logger;
private import std.format: format;
private import std.exception: enforce;
private import std.string: empty;
private import std.typecons: Nullable;

private import thepath: Path;
private import theprocess: resolveProgram, systemUserExists;
private import darkcommand;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.python.venv: VenvOptions, PyInstallType;
private import odood.lib.python.odoo: guessVenvOptions, suggestPythonVersion;
private import odood.lib.project: Project, OdooInstallType;
private import odood.lib.project.config: ProjectConfigOdoo, ProjectConfigDirectories;
private import odood.lib.odoo.config: initOdooConfig;
private import odood.lib.postgres: createNewPostgresUser;
private import odood.utils.odoo.serie: OdooSerie;


class CommandInit: OdoodCommand {
    string installDir;
    string odooVersion = "17.0";
    string installType = "archive";
    Nullable!string odooBranch;
    Nullable!string odooRepo;
    bool pyenv;
    Nullable!string pyVersion;
    Nullable!string nodeVersion;
    string dbHost = "localhost";
    string dbPort = "False";
    string dbUser = "odoo";
    string dbPassword = "odoo";
    bool createDbUser;
    string httpHost = "0.0.0.0";
    string httpPort = "8069";
    bool logToStderr;

    this() {
        super("init", "Initialize new odood project.");
        this.addOption!(installDir)("i", "install-dir", "Directory to install odoo to");
        this.addOption!(odooVersion)("v", "odoo-version", "Version of Odoo to install")
            .defaultValue("17.0");
        this.addOption!(installType)("", "install-type",
            "Installation type. Accept values: git, archive. Default: archive.")
            .defaultValue("archive")
            .acceptsValues(["git", "archive"]);
        this.addOption!(odooBranch)("", "odoo-branch",
            "Branch in Odoo repo to install Odoo from.");
        this.addOption!(odooRepo)("", "odoo-repo",
            "Install Odoo from specific repository.");
        this.addFlag!(pyenv)("", "pyenv",
            "Use python from pyenv to initialize virtualenv for project. Install desired py version if needed");
        this.addOption!(pyVersion)("", "py-version",
            "Install specific python version. By default system python used");
        this.addOption!(nodeVersion)("", "node-version", "Install specific node version.");
        this.addOption!(dbHost)("", "db-host", "Database host").defaultValue("localhost");
        this.addOption!(dbPort)("", "db-port", "Database port").defaultValue("False");
        this.addOption!(dbUser)("", "db-user", "Database user").defaultValue("odoo");
        this.addOption!(dbPassword)("", "db-password", "Database password").defaultValue("odoo");
        this.addFlag!(createDbUser)("", "create-db-user",
            "[sudo] Create database user automatically during installation. Requires sudo.");
        this.addOption!(httpHost)("", "http-host", "Http host").defaultValue("0.0.0.0");
        this.addOption!(httpPort)("", "http-port", "Http port").defaultValue("8069");
        this.addFlag!(logToStderr)("", "log-to-stderr",
            "Configure project without a log file (logs to stdout/stderr). " ~
            "Recommended for container deployments.");
    }

    auto prepareOdooConfig(in Project project) {
        auto odoo_config = initOdooConfig(project);
        odoo_config["options"].setKey("db_host", dbHost);
        odoo_config["options"].setKey("db_port", dbPort);
        odoo_config["options"].setKey("db_user", dbUser);
        odoo_config["options"].setKey("db_password", dbPassword);

        if (project.odoo.serie < OdooSerie(11)) {
            odoo_config["options"].setKey("xmlrpc_interface", httpHost);
            odoo_config["options"].setKey("xmlrpc_port", httpPort);
        } else {
            odoo_config["options"].setKey("http_interface", httpHost);
            odoo_config["options"].setKey("http_port", httpPort);
        }
        return odoo_config;
    }

    override int execute() {
        auto odoo_version = OdooSerie(odooVersion);
        auto odoo_branch = odooBranch.isNull ? odoo_version.toString() : odooBranch.get;
        auto odoo_repo_url = odooRepo.isNull ?
            "https://github.com/odoo/odoo.git" : odooRepo.get;

        enforce!OdoodCLIException(
            odoo_version.isValid,
            "Odoo version %s is not valid".format(odooVersion));

        if (createDbUser)
            enforce!OdoodCLIException(
                systemUserExists("postgres"),
                "Local 'postgresql' package seems not installed, thus cannot create pg user for Odoo!");

        OdooInstallType install_type = OdooInstallType.Archive;
        switch(installType) {
            case "git":
                install_type = OdooInstallType.Git;
                break;
            case "archive":
                install_type = OdooInstallType.Archive;
                break;
            default:
                assert(0, "Unsupported installation type");
        }

        auto root = Path(installDir).toAbsolute;
        auto directories = ProjectConfigDirectories(root);
        auto project_odoo = ProjectConfigOdoo(
            root, directories, odoo_version, odoo_branch, odoo_repo_url);
        if (logToStderr)
            project_odoo.logfile.nullify;
        auto project = new Project(root, directories, project_odoo);

        auto odoo_config = prepareOdooConfig(project);

        VenvOptions venv_options = project.odoo.serie.guessVenvOptions;

        if (!pyVersion.isNull) {
            venv_options.py_version = pyVersion.get;
            venv_options.install_type = PyInstallType.Build;
        }
        if (!nodeVersion.isNull)
            venv_options.node_version = nodeVersion.get;

        if (pyenv) {
            venv_options.install_type = PyInstallType.PyEnv;
            if (venv_options.py_version.empty)
                venv_options.py_version = odoo_version.suggestPythonVersion;

            enforce!OdoodCLIException(!resolveProgram("pyenv").isNull, "pyenv not available!");
        }

        project.initialize(odoo_config, venv_options, install_type);
        project.save();

        if (createDbUser) {
            infof(
                "Creating new postgres user %s for Odood project %s",
                dbUser, project.project_root);
            createNewPostgresUser(dbUser, dbPassword);
        }
        return 0;
    }
}
