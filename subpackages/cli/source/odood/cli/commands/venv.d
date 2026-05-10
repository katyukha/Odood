module odood.cli.commands.venv;

private import std.typecons: Nullable;

private import thepath: Path;
private import darkcommand;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project, OdooInstallType;
private import odood.lib.install;
private import odood.lib.venv: PyInstallType, PyRequirements;
private import odood.lib.odoo.python: guessVenvOptions;
private import odood.utils.odoo.serie: OdooSerie;


class CommandVenvInstallDevTools: OdoodCommand {

    this() {
        super("install-dev-tools", "Install Dev Tools");
    }

    override int execute() {
        auto project = Project.loadProject;

        project.venv.installPyPackages(
            "coverage",
            "setproctitle",
            "watchdog",
            "pylint-odoo<8.0",
            "flake8",
            "websocket-client",
            "jingtrang",
            "pre-commit");

        project.venv.installJSPackages("eslint");
        project.venv.installPyPackages("git+https://github.com/OCA/odoo-module-migrator@master");
        return 0;
    }
}


class CommandVenvInstallPyPackages: OdoodCommand {
    Nullable!Path requirements;
    string[] package_;

    this() {
        super("install-py-packages", "Install Python packages");
        this.addOption!(requirements)("r", "requirements",
            "Path to requirements.txt to install python packages from")
            .acceptsFiles();
        this.addArgument!(package_)("package", "Python package specification to install.")
            .defaultValue([]);
    }

    override int execute() {
        auto project = Project.loadProject;

        if (!requirements.isNull)
            project.venv.installPyRequirements(requirements.get);
        if (package_.length > 0)
            project.venv.installPyPackages(package_);
        return 0;
    }
}


class CommandVenvPIP: OdoodCommand {

    this() {
        super("pip", "Run pip for this environment. All arguments after '--' will be forwarded directly to pip.");
    }

    override int execute() {
        Project.loadProject.venv.runner
            .withArgs("pip")
            .withArgs(argsRest)
            .execv;
        return 0;
    }
}


class CommandVenvNPM: OdoodCommand {

    this() {
        super("npm", "Run npm for this environment. All arguments after '--' will be forwarded directly to npm.");
    }

    override int execute() {
        Project.loadProject.venv.runner
            .withArgs("npm")
            .withArgs(argsRest)
            .execv;
        return 0;
    }
}


class CommandVenvIPython: OdoodCommand {

    this() {
        super("ipython", "Run ipython in this environment. All arguments after '--' will be forwarded directly to IPython.");
    }

    override int execute() {
        auto project = Project.loadProject;

        if (!project.venv.path.join("bin", "ipython").exists)
            project.venv.installPyPackages("ipython");

        project.venv.runner
            .withArgs("ipython")
            .withArgs(argsRest)
            .execv;
        return 0;
    }
}


class CommandVenvPython: OdoodCommand {

    this() {
        super("python", "Run python for this environment. All arguments after '--' will be forwarded directly to python.");
    }

    override int execute() {
        auto project = Project.loadProject;
        project.venv.runner
            .withArgs("python")
            .withArgs(argsRest)
            .execv;
        return 0;
    }
}


class CommandVenvLOdoo: OdoodCommand {

    this() {
        super("lodoo", "Run lodoo in this environment. All arguments after '--' will be forwarded directly to lodoo.");
    }

    override int execute() {
        auto project = Project.loadProject;

        if (!project.venv.path.join("bin", "lodoo").exists)
            project.venv.installPyPackages("lodoo");

        project.lodoo.runner
            .withArgs(argsRest)
            .execv;
        return 0;
    }
}


class CommandVenvRun: OdoodCommand {

    this() {
        immutable string description = "" ~
            "Run command in this virtual environment. " ~
            "The command and all arguments must be specified after '--'. " ~
            "For example: 'odood venv run -- ipython'";
        super("run", description);
    }

    override int execute() {
        Project.loadProject.venv.runner.withArgs(argsRest).execv;
        return 0;
    }
}


class CommandVenvReinstall: OdoodCommand {
    Nullable!string pyVersion;
    Nullable!string nodeVersion;

    this() {
        super("reinstall", "Reinstall virtualenv.");
        this.addOption!(pyVersion)("", "py-version", "Install specific python version.");
        this.addOption!(nodeVersion)("", "node-version", "Install specific node version.");
    }

    override int execute() {
        auto project = Project.loadProject;

        auto venv_options = project.odoo.serie.guessVenvOptions;

        if (!pyVersion.isNull) {
            venv_options.py_version = pyVersion.get;
            venv_options.install_type = PyInstallType.Build;
        }
        if (!nodeVersion.isNull)
            venv_options.node_version = nodeVersion.get;

        if (project.venv.path.exists)
            project.venv.path.remove();

        project.installVirtualenv(venv_options);
        project.installOdoo();

        PyRequirements reqs;
        foreach(addon; project.addons.scan())
            if (addon.path.join("requirements.txt").exists())
                reqs.addRequirementsFile(addon.path.join("requirements.txt"));
        if (!reqs.empty)
            project.venv.installBatchPyRequirements(reqs);
        return 0;
    }
}


class CommandVenvUpdateOdoo: OdoodCommand {
    bool backup;

    this() {
        super("update-odoo", "Update Odoo itself.");
        this.addFlag!(backup)("b", "backup", "Backup Odoo before update.");
    }

    override int execute() {
        auto project = Project.loadProject;
        bool start_server = false;
        if (project.server.isRunning()) {
            start_server = true;
            project.server.stop();
        }

        project.updateOdoo(backup);

        if (start_server)
            project.server.start;
        return 0;
    }
}


class CommandVenvReinstallOdoo: OdoodCommand {
    bool backup;
    bool noBackup;
    Nullable!string venvPyVersion;
    Nullable!string venvNodeVersion;
    string installType = "archive";
    Nullable!string version_;

    this() {
        super("reinstall-odoo", "Reinstall Odoo to different Odoo version.");
        this.addFlag!(backup)("b", "backup", "Backup Odoo before update.");
        this.addFlag!(noBackup)("", "no-backup", "Do not take backup of Odoo and venv.");
        this.addOption!(venvPyVersion)("", "venv-py-version", "Install specific python version.");
        this.addOption!(venvNodeVersion)("", "venv-node-version", "Install specific node version.");
        this.addOption!(installType)("", "install-type",
            "Installation type. Accept values: git, archive. Default: archive.")
            .defaultValue("archive")
            .acceptsValues(["git", "archive"]);
        this.addOption!(version_)("v", "version", "Odoo version to install.");
    }

    override int execute() {
        auto project = Project.loadProject;
        bool start_server = false;
        if (project.server.isRunning()) {
            start_server = true;
            project.server.stop();
        }

        OdooInstallType install_type = OdooInstallType.Archive;
        switch(installType) {
            case "git":
                install_type = OdooInstallType.Git;
                break;
            case "archive":
                install_type = OdooInstallType.Archive;
                break;
            default:
                install_type = project.odoo_install_type;
                break;
        }

        auto reinstall_version = version_.isNull ?
            project.odoo.serie : OdooSerie(version_.get);

        auto venv_options = reinstall_version.guessVenvOptions;

        if (!venvPyVersion.isNull) {
            venv_options.py_version = venvPyVersion.get;
            venv_options.install_type = PyInstallType.Build;
        }
        if (!venvNodeVersion.isNull)
            venv_options.node_version = venvNodeVersion.get;

        project.reinstallOdoo(
            reinstall_version,
            install_type,
            venv_options,
            !noBackup || backup,
        );

        if (start_server)
            project.server.start;
        return 0;
    }
}


class CommandVenv: OdoodCommand {
    this() {
        super("venv", "Manage virtual environment for this project.");
        this.add(new CommandVenvInstallDevTools());
        this.add(new CommandVenvInstallPyPackages());
        this.add(new CommandVenvReinstall());
        this.add(new CommandVenvUpdateOdoo());
        this.add(new CommandVenvReinstallOdoo());
        this.add(new CommandVenvPIP());
        this.add(new CommandVenvNPM());
        this.add(new CommandVenvIPython());
        this.add(new CommandVenvPython());
        this.add(new CommandVenvLOdoo());
        this.add(new CommandVenvRun());
    }
}
