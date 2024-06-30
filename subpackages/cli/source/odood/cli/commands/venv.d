module odood.cli.commands.venv;

private import commandr: Argument, Option, Flag, ProgramArgs, acceptsValues;
private import thepath: Path;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project, OdooInstallType;
private import odood.utils.odoo.serie: OdooSerie;



class CommandVenvInstallDevTools: OdoodCommand {

    this() {
        super("install-dev-tools", "Install Dev Tools");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        project.venv.installPyPackages(
            "coverage",
            "setproctitle",
            "watchdog",
            "pylint-odoo<8.0",
            "flake8",
            "websocket-client",
            "jingtrang");

        project.venv.installJSPackages("eslint");
    }

}


class CommandVenvInstallPyPackages: OdoodCommand {

    this() {
        super("install-py-packages", "Install Python packages");
        this.add(new Option(
            "r", "requirements", "Path to requirements.txt to install python packages from"));
        this.add(new Argument(
            "package", "Python package specification to install").repeating.optional);

    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        if (args.option("requirements"))
            project.venv.installPyRequirements(Path(args.option("requirements")));
        if (args.args("package").length > 0)
            project.venv.installPyPackages(args.args("package"));
    }

}


class CommandVenvPIP: OdoodCommand {

    this() {
        super("pip", "Run pip for this environment. All arguments after '--' will be forwarded directly to pip.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        project.venv.runner
            .addArgs("pip")
            .addArgs(args.argsRest)
            .execv;
    }

}


class CommandVenvNPM: OdoodCommand {

    this() {
        super("npm", "Run npm for this environment. All arguments after '--' will be forwarded directly to npm.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        project.venv.runner
            .addArgs("npm")
            .addArgs(args.argsRest)
            .execv;
    }

}


class CommandVenvPython: OdoodCommand {

    this() {
        super("python", "Run python for this environment. All arguments after '--' will be forwarded directly to python.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        project.venv.runner
            .addArgs("python")
            .addArgs(args.argsRest)
            .execv;
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

    public override void execute(ProgramArgs args) {
        Project.loadProject.venv.runner.addArgs(args.argsRest).execv;
    }

}

class CommandVenvReinstall: OdoodCommand {

    this() {
        super("reinstall", "Reinstall virtualenv.");
        this.add(new Option(
            null, "py-version", "Install specific python version.")
                .defaultValue("auto"));
        this.add(new Option(
            null, "node-version", "Install specific node version.")
                .defaultValue("lts"));
    }

    public override void execute(ProgramArgs args) {
        import odood.lib.install;
        auto project = Project.loadProject;

        if (project.venv.path.exists)
            project.venv.path.remove();

        project.installVirtualenv(
            args.option("py-version", "auto"),
            args.option("node-version", "lts"));
        project.installOdoo();

        foreach(addon; project.addons.scan())
            if (addon.path.join("requirements.txt").exists())
                project.venv.installPyRequirements(
                    addon.path.join("requirements.txt"));
    }

}


class CommandVenvUpdateOdoo: OdoodCommand {

    this() {
        super("update-odoo", "Update Odoo itself.");
        this.add(new Flag(
            "b", "backup", "Backup Odoo before update."));
    }

    public override void execute(ProgramArgs args) {
        import odood.lib.install;
        auto project = Project.loadProject;
        bool start_server = false;
        if (project.server.isRunning()) {
            start_server = true;
            project.server.stop();
        }

        project.updateOdoo(args.flag("backup"));

        if (start_server)
            project.server.start;
    }

}


class CommandVenvReinstallOdoo: OdoodCommand {

    this() {
        super("reinstall-odoo", "Reinstall Odoo to different Odoo version.");
        this.add(new Flag(
            "b", "backup", "Backup Odoo before update."));
        this.add(new Flag(
            null, "no-backup", "Do not take backup of Odoo and venv."));
        this.add(new Flag(
            null, "reinstall-venv", "Reinstall virtualenv too..."));
        this.add(new Option(
            null, "venv-py-version", "Install specific python version.")
                .defaultValue("auto"));
        this.add(new Option(
            null, "venv-node-version", "Install specific node version.")
                .defaultValue("lts"));
        this.add(new Option(
            null, "install-type", "Installation type. Accept values: git, archive. Default: archive.")
                .defaultValue("archive")
                .acceptsValues(["git", "archive"]));
        this.add(new Option(
            "v", "version", "Odoo version to install."));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        bool start_server = false;
        if (project.server.isRunning()) {
            start_server = true;
            project.server.stop();
        }

        OdooInstallType install_type = OdooInstallType.Archive;
        switch(args.option("install-type")) {
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

        auto reinstall_version = args.option("version") ?
            OdooSerie(args.option("version")) : project.odoo.serie;

        project.reinstallOdoo(
            reinstall_version,
            install_type,
            !args.flag("no-backup") || args.flag("backup"),
            args.flag("reinstall-venv"),
            args.option("venv-py-version", "auto"),
            args.option("venv-node-version", "lts"),
        );

        if (start_server)
            project.server.start;
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
        this.add(new CommandVenvPython());
        this.add(new CommandVenvRun());
    }
}


