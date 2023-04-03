module odood.cli.commands.venv;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;



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
        if (project.project_root.join("python").exists)
            project.project_root.join("python").remove();

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
    }

    public override void execute(ProgramArgs args) {
        import odood.lib.install;
        auto project = Project.loadProject;
        bool start_server = false;
        if (project.server.isRunning()) {
            start_server = true;
            project.server.stop();
        }

        project.updateOdoo();

        if (start_server)
            project.server.spawn(true);
    }

}


class CommandVenv: OdoodCommand {
    this() {
        super("venv", "Manage virtual environment for this project.");
        this.add(new CommandVenvInstallDevTools());
        this.add(new CommandVenvReinstall());
        this.add(new CommandVenvUpdateOdoo());
    }
}


