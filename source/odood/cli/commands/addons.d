module odood.cli.commands.addons;

private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project, ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.exception: OdoodException;


class CommandAddonsAddRepo: OdoodCommand {
    this() {
        super("add-repo", "Add git repository.");
        this.add(new Option(
            "b", "branch", "Branch to clone"));
        this.add(new Argument("repo", "Repository URL to clone from.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();

        project.addRepo(
            args.arg("repo"),
            args.option("branch") ?
                args.option("branch") : project.config.odoo_branch);
    }

}


class CommandAddonsLink: OdoodCommand {
    this() {
        super("link", "Link addons in specified directory.");
        this.add(new Argument(
            "path", "Path to search for addons in.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();

        project.addons.link(Path(args.arg("path")));
    }

}



class CommandAddons: OdoodCommand {
    this() {
        super("addons", "Manage third-party addons.");
        this.add(new CommandAddonsAddRepo());
        this.add(new CommandAddonsLink());
    }
}

