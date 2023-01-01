module odood.cli.commands.config;

private import commandr: ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;


class CommandConfigUpdate: OdoodCommand {
    this() {
        super("update", "Update the config.");
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        project.save();
    }

}


class CommandConfig: OdoodCommand {
    this() {
        super("config", "Manage config of the project");
        this.add(new CommandConfigUpdate());
    }
}


