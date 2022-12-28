module odood.cli.commands.addons;

private import std.logger;
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


class CommandAddonsUpdateList: OdoodCommand {
    this() {
        super("update-list", "Update list of addons.");
        this.add(
            new Argument(
                "database", "Path to search for addons in."
            ).optional().repeating());
        this.add(new Flag("a", "all", "Update all databases."));
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();

        string[] dbnames = args.flag("all") ?
            project.lodoo.databaseList() : args.args("database");

        foreach(db; dbnames) {
            infof("Updating list of addons for database %s", db);
            project.lodoo.updateAddonsList(db);
        }
    }

}



class CommandAddons: OdoodCommand {
    this() {
        super("addons", "Manage third-party addons.");
        this.add(new CommandAddonsAddRepo());
        this.add(new CommandAddonsLink());
        this.add(new CommandAddonsUpdateList());
    }
}

