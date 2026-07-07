module odood.cli.commands.discover;

private import std.typecons: Nullable;

private import thepath: Path;
private import darkcommand;

private import odood.cli.core: OdoodCommand;
private import odood.project: Project;
private import odood.project.discover: discoverOdooHelper;


class CommandDiscoverOdooHelper: OdoodCommand {
    bool system;
    Nullable!Path path;

    this() {
        super("odoo-helper", "Discover odoo-helper-scripts project.");
        this.addFlag!(system)("s", "system",
            "Discover system (server-wide) odoo-helper project installation.");
        this.addArgument!(path)("path",
            "Try to discover odoo-helper project in specified path.");
    }

    override int execute() {
        auto search_path = system ?
            Path("/", "etc", "odoo-helper.conf") :
            !path.isNull ?
                path.get :
                Path.current;
        auto project = discoverOdooHelper(search_path);
        if (system)
            project.save(Path("/", "etc", "odood.yml"));
        else
            project.save();
        project.venv.ensureRunInVenvExists();
        return 0;
    }
}


class CommandDiscover: OdoodCommand {
    this() {
        super(
            "discover",
            "Discover already installed odoo, " ~
            "and configure Odood to manage it.");
        this.add(new CommandDiscoverOdooHelper());
    }
}
