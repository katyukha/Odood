module odood.cli.commands.ci;

private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.odoo.utils: fixVersionConflict;


class CommandCiFixVersionConflict: OdoodCommand {
    this() {
        super("fix-version-conflict", "Fix version conflicts in provided addons.");
        this.add(new Flag(
            "r", "recursive", "Search for addons recursively."));
        this.add(new Argument(
            "path", "Path to search for addons in."));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto search_path = args.arg("path") ?
            Path(args.arg("path")) : Path.current;
        foreach(addon; project.addons.scan(search_path, args.flag("recursive"))) {
            addon.path.join("__manifest__.py").fixVersionConflict(project.odoo.serie);
        }
    }
}


class CommandCi: OdoodCommand {
    this() {
        super(
            "ci",
            "Various utility functions, mostly usefule for CI processes.");
        this.add(new CommandCiFixVersionConflict());
    }
}

