module odood.cli.commands.addons;

private import std.stdio;
private import std.logger;
private import std.format: format;
private import std.exception: enforce;
private import std.algorithm: sort;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;
private import colored;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.addons.addon: OdooAddon;
private import odood.lib.exception: OdoodException;


enum AddonDisplayType {
    by_name,
    by_path,
    by_name_version,
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
            null, "by-name-version", "Display addon name with addon version"));
        this.add(new Flag(
            "s", "system", "Search for all addons available for Odoo."));
        this.add(new Flag(
            "r", "recursive", "Search for addons recursively."));
        this.add(new Flag(
            null, "installable", "Filter only installable addons."));
        this.add(new Flag(
            null, "not-installable", "Filter only not-installable addons."));
        this.add(new Flag(
            null, "linked", "Filter only linked addons."));
        this.add(new Flag(
            null, "not-linked", "Filter only addons that are not linked."));
        this.add(new Option(
            "c", "color",
            "Color output by selected scheme: " ~
            "link - color addons by link status"));
        this.add(new Argument(
            "path", "Path to search for addons in.").optional);
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto search_path = args.arg("path") ?
            Path(args.arg("path")) : Path.current;

        auto display_type = AddonDisplayType.by_name;
        if (args.flag("by-path"))
            display_type = AddonDisplayType.by_path;
        if (args.flag("by-name"))
            display_type = AddonDisplayType.by_name;
        if (args.flag("by-name-version"))
            display_type = AddonDisplayType.by_name_version;

        OdooAddon[] addons;
        if (args.flag("system")) {
            writeln("Listing all addons available for Odoo");
            addons = project.addons.scan();
        } else  {
            writeln("Listing addons in ", search_path.toString.yellow);
            addons = project.addons.scan(search_path, args.flag("recursive"));
        }

        foreach(addon; addons.sort!((a, b) => a.name < b.name)) {
            if (args.flag("installable") && !addon.manifest.installable)
                continue;
            if (args.flag("not-installable") && addon.manifest.installable)
                continue;
            if (args.flag("linked") && !project.addons.isLinked(addon))
                continue;
            if (args.flag("not-linked") && project.addons.isLinked(addon))
                continue;

            string addon_line;
            final switch(display_type) {
                case AddonDisplayType.by_name:
                    addon_line = addon.name;
                    break;
                case AddonDisplayType.by_path:
                    addon_line = addon.path.toString;
                    break;
                case AddonDisplayType.by_name_version:
                    addon_line = "%10s\t%s".format(
                        addon.manifest.module_version, addon.name);
                    break;
            }

            if (args.option("color") == "link") {
                if (project.addons.isLinked(addon))
                    writeln(addon_line.green);
                else
                    writeln(addon_line.red);
            } else {
                writeln(addon_line);
            }
        }
    }

}


class CommandAddonsLink: OdoodCommand {
    this() {
        super("link", "Link addons in specified directory.");
        this.add(new Flag(
            "f", "force", "Rewrite already linked/existing addon."));
        this.add(new Flag(
            "r", "recursive",
            "Search for addons in this directory recursively."));
        this.add(new Flag(
            null, "ual", "Update addons list for all databases"));
        this.add(new Argument(
            "path", "Path to search for addons in.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        project.addons.link(
            Path(args.arg("path")),
            args.flag("recursive"),
            args.flag("force"));

        if (args.flag("ual"))
            foreach(dbname; project.lodoo.databaseList())
                project.lodoo.updateAddonsList(dbname);
    }

}


class CommandAddonsUpdateList: OdoodCommand {
    this() {
        this("update-list");
    }

    this(in string name) {
        super(name, "Update list of addons.");
        this.add(
            new Argument(
                "database", "Path to search for addons in."
            ).optional().repeating());
        this.add(new Flag("a", "all", "Update all databases."));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        string[] dbnames = args.flag("all") ?
            project.lodoo.databaseList() : args.args("database");

        if (!dbnames)
            errorf("No databases specified.");

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
            ).repeating());
        this.add(
            new Option(
                null, "dir", "Directory to search for addons to be updated"
            ).repeating());
        this.add(
            new Option(
                null, "dir-r", "Directory to recursively search for addons to be installed"
            ).repeating());
        this.add(
            new Flag(
                "a", "all", "Update all modules"));
        this.add(
            new Argument(
                "addon", "Name of addon to update").optional().repeating());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        string[] dbnames = args.options("db") ?
            args.options("db") : project.lodoo.databaseList();

        OdooAddon[] addons;
        if (!args.flag("all")) {
            foreach(addon_name; args.args("addon")) {
                auto addon = project.addons.getByString(addon_name);
                enforce!OdoodException(
                    !addon.isNull,
                    "%s does not look like addon name or path to addon".format(
                        addon_name));
                addons ~= addon.get;
            }

            foreach(dir; args.options("dir"))
                foreach(addon; project.addons.scan(Path(dir)))
                    addons ~= addon;

            foreach(dir; args.options("dir-r"))
                foreach(addon; project.addons.scan(Path(dir), true))
                    addons ~= addon;
        }

        auto start_again=false;
        if (project.server.isRunning) {
            project.server.stop;
            start_again=true;
        }

        foreach(db; dbnames) {
            if (args.flag("all"))
                project.addons.updateAll(db);
            else
                project.addons.update(db, addons);
        }

        if (start_again)
            project.server.spawn(true);
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
            new Option(
                null, "dir-r", "Directory to recursively search for addons to be installed"
            ).optional().repeating());
        this.add(
            new Argument(
                "addon", "Name of addon to install").optional().repeating());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        string[] dbnames = args.options("db") ?
            args.options("db") : project.lodoo.databaseList();

        OdooAddon[] addons;
        foreach(addon_name; args.args("addon")) {
            auto addon = project.addons.getByString(addon_name);
            enforce!OdoodException(
                !addon.isNull,
                "%s does not look like addon name or path to addon".format(
                    addon_name));
            addons ~= addon.get;
        }

        foreach(dir; args.options("dir"))
            foreach(addon; project.addons.scan(Path(dir)))
                addons ~= addon;

        foreach(dir; args.options("dir-r"))
            foreach(addon; project.addons.scan(Path(dir), true))
                addons ~= addon;

        auto start_again=false;
        if (project.server.isRunning) {
            project.server.stop;
            start_again=true;
        }

        foreach(db; dbnames) {
            project.addons.install(db, addons);
        }

        if (start_again)
            project.server.spawn(true);
    }
}


class CommandAddonsUninstall: OdoodCommand {
    this() {
        super("uninstall", "Uninstall specified addons.");
        this.add(
            new Option(
                "d", "db", "Database(s) to uninstall addons in."
            ).optional().repeating());
        this.add(
            new Option(
                null, "dir", "Directory to search for addons to be uninstalled"
            ).optional().repeating());
        this.add(
            new Option(
                null, "dir-r", "Directory to recursively search for addons to be uninstalled"
            ).optional().repeating());
        this.add(
            new Argument(
                "addon", "Name of addon to uninstall").optional().repeating());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        string[] dbnames = args.options("db") ?
            args.options("db") : project.lodoo.databaseList();

        OdooAddon[] addons;
        foreach(addon_name; args.args("addon")) {
            auto addon = project.addons.getByString(addon_name);
            enforce!OdoodException(
                !addon.isNull,
                "%s does not look like addon name or path to addon".format(
                    addon_name));
            addons ~= addon.get;
        }

        foreach(dir; args.options("dir"))
            foreach(addon; project.addons.scan(Path(dir)))
                addons ~= addon;

        foreach(dir; args.options("dir-r"))
            foreach(addon; project.addons.scan(Path(dir), true))
                addons ~= addon;

        auto start_again=false;
        if (project.server.isRunning) {
            project.server.stop;
            start_again=true;
        }

        foreach(db; dbnames) {
            project.addons.uninstall(db, addons);
        }

        if (start_again)
            project.server.spawn(true);
    }
}


class CommandAddonsAdd: OdoodCommand {
    this() {
        super("add", "Add addons to the project");
        this.add(new Flag(
            null, "single-branch",
            "Clone repository wihth --single-branch options. " ~
            "This could significantly reduce size of data to be downloaded " ~
            "and increase performance."));
        this.add(new Option(
            null, "odoo-apps", "Add addon from odoo apps.").repeating);
        this.add(new Option(
            null, "odoo-requirements",
            "Add modules (repos) from odoo_requirements.txt file, " ~
            "that is used by odoo-helper-scripts.").repeating);
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        foreach(app; args.options("odoo-apps"))
            project.addons.downloadFromOdooApps(app);

        foreach(requirements_path; args.options("odoo-requirements"))
            project.addons.processOdooRequirements(
                Path(requirements_path),
                args.flag("single-branch"));
    }

}


class CommandAddonsIsInstalled: OdoodCommand {
    this() {
        super(
            "is-installed",
            "Print list of databases wehre specified addon is installed.");
        this.add(new Argument(
            "addon", "Name of addon or path to addon to check."));
    }

    public override void execute(ProgramArgs args) {
        import dpq.query;
        auto project = Project.loadProject;

        auto addon_n = project.addons.getByString(args.arg("addon"));
        enforce!OdoodException(
            !addon_n.isNull,
            "Cannot find addon %s".format(args.arg("addon")));
        auto addon = addon_n.get();

        foreach(dbname; project.lodoo.databaseList)
            if (project.addons.isInstalled(dbname, addon))
                writeln(dbname);
    }
}



class CommandAddons: OdoodCommand {
    this() {
        super("addons", "Manage third-party addons.");
        this.add(new CommandAddonsLink());
        this.add(new CommandAddonsUpdateList());
        this.add(new CommandAddonsList());
        this.add(new CommandAddonsUpdate());
        this.add(new CommandAddonsInstall());
        this.add(new CommandAddonsUninstall());
        this.add(new CommandAddonsAdd());
        this.add(new CommandAddonsIsInstalled());
    }
}

