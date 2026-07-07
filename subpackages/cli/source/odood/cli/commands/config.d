module odood.cli.commands.config;

private import odood.cli.core: OdoodCommand;
private import odood.project: Project;


class CommandConfigUpdate: OdoodCommand {
    this() {
        super("update", "Update the config.");
    }

    override int execute() {
        auto project = Project.loadProject;
        project.save();
        return 0;
    }

}


class CommandConfig: OdoodCommand {
    this() {
        super("config", "Manage config of the project");
        this.add(new CommandConfigUpdate());
    }
}
