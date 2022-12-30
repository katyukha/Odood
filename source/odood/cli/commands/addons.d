module odood.cli.commands.addons;

private import std.stdio;
private import std.logger;
private import std.format: format;
private import std.exception: enforce;
private import std.algorithm: sort;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project, ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.addon: OdooAddon;
private import odood.lib.exception: OdoodException;

enum AddonDisplayType {
    by_name,
    by_path,
}


class CommandAddonsList: OdoodCommand {
    this() {
        this("list");
    }

    this(in string name) {
        super(name, "List addons in specified directory.");
        this.add(new Flag(
            null, "by-path", "Display addons by paths."));
        this.add(new Flag(
            null, "by-name", "Display addons by name (default)."));
        this.add(new Flag(
            null, "system", "Search for all addons available for Odoo."));
        this.add(new Argument(
            "path", "Path to search for addons in.").optional);
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();

        auto search_path = args.arg("path") ?
            Path(args.arg("path")) : Path.current;

        auto display_type = AddonDisplayType.by_name;
        if (args.flag("by-path"))
            display_type = AddonDisplayType.by_path;
        if (args.flag("by-name"))
            display_type = AddonDisplayType.by_name;

        OdooAddon[] addons;
        if (args.flag("system")) {
            info("Listing all addons available for Odoo");
            addons = project.addons.scan();
        } else  {
            infof("Listing addons in %s", search_path);
            addons = project.addons.scan(search_path);
        }

        foreach(addon; addons.sort!((a, b) => a.name < b.name)) {
            final switch(display_type) {
                case AddonDisplayType.by_name:
                    writeln(addon.name);
                    break;
                case AddonDisplayType.by_path:
                    writeln(addon.path);
                    break;
            }
        }
    }

}


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


class CommandAddonsUpdate: OdoodCommand {
    this() {
        super("update", "Update specified addons.");
        this.add(
            new Option(
                "d", "db", "Database(s) to update addons in."
            ).optional().repeating());
        this.add(
            new Option(
                null, "dir", "Directory to search for addons to be updated"
            ).optional().repeating());
        this.add(
            new Argument(
                "addon", "Name of addon to update").optional().repeating());
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();

        string[] dbnames = args.options("db") ?
            args.options("db") : project.lodoo.databaseList();

        string[] addon_names = args.args("addon");

        foreach(dir; args.options("dir"))
            foreach(addon; project.addons.scan(Path(dir)))
                addon_names ~= [addon.name];

        tracef(
            "Addons to be updated in databases %s: %s", dbnames, addon_names);
        foreach(db; dbnames) {
            infof("Updating addons for <yellow>%s</yellow> database...", db);
            project.addons.update(addon_names, db);
        }
    }

}


class CommandAddonsInstall: OdoodCommand {
    this() {
        super("install", "Install specified addons.");
        this.add(
            new Option(
                "d", "db", "Database(s) to install addons in."
            ).optional().repeating());
        this.add(
            new Option(
                null, "dir", "Directory to search for addons to be installed"
            ).optional().repeating());
        this.add(
            new Argument(
                "addon", "Name of addon to update").optional().repeating());
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();

        string[] dbnames = args.options("db") ?
            args.options("db") : project.lodoo.databaseList();

        string[] addon_names = args.args("addon");

        foreach(dir; args.options("dir"))
            foreach(addon; project.addons.scan(Path(dir)))
                addon_names ~= [addon.name];

        tracef(
            "Addons to be installed in databases %s: %s", dbnames, addon_names);
        foreach(db; dbnames) {
            infof("Installing addons for <yellow>%s</yellow> database...", db);
            project.addons.update(addon_names, db);
        }
    }

}



class CommandAddons: OdoodCommand {
    this() {
        super("addons", "Manage third-party addons.");
        this.add(new CommandAddonsAddRepo());
        this.add(new CommandAddonsLink());
        this.add(new CommandAddonsUpdateList());
        this.add(new CommandAddonsList());
        this.add(new CommandAddonsUpdate());
        this.add(new CommandAddonsInstall());
    }
}

