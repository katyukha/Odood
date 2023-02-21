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


class CommandVenv: OdoodCommand {
    this() {
        super("venv", "Manage virtual environment for this project.");
        this.add(new CommandVenvInstallDevTools());
    }
}


