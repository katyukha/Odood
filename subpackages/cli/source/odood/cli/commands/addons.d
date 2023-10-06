module odood.cli.commands.addons;

private import std.stdio;
private import std.logger;
private import std.format: format;
private import std.exception: enforce, basicExceptionCtors;
private import std.algorithm;
private import std.conv: to;
private import std.string: capitalize, strip, join;
private import std.regex;
private import std.array;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;
private import colored;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.cli.utils: printLogRecordSimplified;
private import odood.lib.project: Project;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.addons.addon: OdooAddon;
private import odood.lib.odoo.log: OdooLogProcessor;
private import odood.lib.server.exception: ServerCommandFailedException;


/** This exception could be throwed when install/update/uninstall command
  * failed.
  **/
class AddonsInstallUpdateUninstallFailed : OdoodCLIException {
    mixin basicExceptionCtors;
}


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
        this.add(new Flag(
            null, "with-price", "Filter only addons that has price defined."));
        this.add(new Flag(
            null, "without-price",
            "Filter only addons that does not have price defined."));
        this.add(new Flag(
            "t", "table", "Display list of addons as table"));
        this.add(new Option(
            "f", "field",
            "Display provided field in table. " ~
            "This have to be valid field from manifest.").repeating);
        this.add(new Option(
            "c", "color",
            "Color output by selected scheme: " ~
            "link - color addons by link status, " ~
            "installable - color addons by installable state."));
        this.add(new Argument(
            "path", "Path to search for addons in.").optional);
    }

    private auto parseDisplayType(ProgramArgs args) {
        if (args.flag("by-path"))
            return AddonDisplayType.by_path;
        if (args.flag("by-name"))
            return AddonDisplayType.by_name;
        if (args.flag("by-name-version"))
            return AddonDisplayType.by_name_version;
        return AddonDisplayType.by_name;
    }

    private auto findAddons(ProgramArgs args, in Project project) {
        auto search_path = args.arg("path") ?
            Path(args.arg("path")) : Path.current;

        OdooAddon[] addons;
        if (args.flag("system")) {
            info("Listing all addons available for Odoo");
            addons = project.addons.scan();
        } else  {
            infof("Listing addons in %s", search_path.toString.yellow);
            addons = project.addons.scan(search_path, args.flag("recursive"));
        }

        return addons
            .sort!((a, b) => a.name < b.name)
            .filter!((addon) {
                if (args.flag("installable") && !addon.manifest.installable)
                    return false;
                if (args.flag("not-installable") && addon.manifest.installable)
                    return false;
                if (args.flag("linked") && !project.addons.isLinked(addon))
                    return false;
                if (args.flag("not-linked") && project.addons.isLinked(addon))
                    return false;
                if (args.flag("with-price") && !addon.manifest.price.is_set)
                    return false;
                if (args.flag("without-price") && addon.manifest.price.is_set)
                    return false;
                return true;
            });
    }

    private string getAddonDisplayName(
            OdooAddon addon,
            in AddonDisplayType display_type) {
        final switch(display_type) {
            case AddonDisplayType.by_name:
                return addon.name;
            case AddonDisplayType.by_path:
                return addon.path.toString;
            case AddonDisplayType.by_name_version:
                return "%10s\t%s".format(
                    addon.manifest.module_version.toString, addon.name);
        }
    }

    private auto getColoredAddonLine(
            ProgramArgs args,
            in Project project,
            OdooAddon addon,
            in AddonDisplayType display_type) {

        // Choose the way to display addon line
        auto addon_line = StyledString(getAddonDisplayName(addon, display_type));

        // Color the addon line to be displayed
        switch(args.option("color")) {
            case "link":
                return project.addons.isLinked(addon) ?
                    addon_line.green : addon_line.red;
            case "installable":
                return addon.manifest.installable ?
                    addon_line.green : addon_line.red;
            case "price":
                return addon.manifest.price.is_set ?
                    addon_line.yellow : addon_line.blue;
            default:
                // Do nothing in case of wrong color or no color
                warningf(
                    args.option("color").length > 0,
                    "Unknown color option '%s'", args.option("color"));
                break;
        }
        return addon_line;
    }

    /** Display addons as plain list
      **/
    private void displayAddonsList(ProgramArgs args, in Project project) {
        auto display_type = parseDisplayType(args);
        foreach(addon; findAddons(args, project))
            writeln(
                getColoredAddonLine(args, project, addon, display_type));
    }

    private string[] prepareAddonsTableHeader(
            ProgramArgs args,
            in string[] fields) {
        string[] header = ["Name".bold.to!string];
        foreach(field; fields)
            switch(field) {
                case "version":
                    header ~= ["Version".bold.to!string];
                    break;
                case "price":
                    header ~= [
                        "Price".bold.to!string,
                        "Currency".bold.to!string,
                    ];
                    break;
                default:
                    header ~= [field.capitalize.bold.to!string];
                    break;
            }
        return header;
    }

    private string[] prepareAddonsTableRow(
            ProgramArgs args,
            in string[] fields,
            in Project project,
            OdooAddon addon,
            in AddonDisplayType display_type) {
        string[] row = [
            getColoredAddonLine(
                args, project, addon, display_type).to!string,
        ];
        foreach(field; fields) {
            switch(field) {
                case "name":
                    row ~= [addon.manifest.name];
                    break;
                case "version":
                    row ~= [addon.manifest.module_version.toString];
                    break;
                case "author":
                    row ~= [addon.manifest.author];
                    break;
                case "category":
                    row ~= [addon.manifest.category];
                    break;
                case "license":
                    row ~= [addon.manifest.license];
                    break;
                case "maintainer":
                    row ~= [addon.manifest.maintainer];
                    break;
                case "auto_install":
                    row ~= [addon.manifest.auto_install.to!string];
                    break;
                case "application":
                    row ~= [addon.manifest.application.to!string];
                    break;
                case "installable":
                    row ~= [addon.manifest.installable.to!string];
                    break;
                case "tags":
                    row ~= [addon.manifest.tags.join(", ")];
                    break;
                case "price":
                    if (addon.manifest.price.is_set)
                        row ~= [
                            addon.manifest.price.price.to!string,
                            addon.manifest.price.currency,
                        ];
                    else
                        row ~= ["", ""];
                    break;
                default:
                    throw new OdoodCLIException("Unsupported manifest field %s".format(field));
            }
        }
        return row;
    }

    /** Display addons as table
      **/
    private void displayAddonsTable(ProgramArgs args, in Project project) {
        import tabletool;
        string[][] table_data;
        auto display_type = parseDisplayType(args);

        string[] fields = args.options("field").length > 0 ?
            args.options("field") : ["version", "price", "installable"];

        table_data ~= prepareAddonsTableHeader(args, fields);

        foreach(addon; findAddons(args, project))
            table_data ~= prepareAddonsTableRow(
                    args, fields, project, addon, display_type);
        writeln(
            tabulate(
                table_data,
                tabletool.Config(
                    tabletool.Style.grid,
                    tabletool.Align.left,
                    true,
                )
            )
        );
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        if (args.flag("table"))
            displayAddonsTable(args, project);
        else
            displayAddonsList(args, project);
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
            null, "manifest-requirements",
            "Install python dependencies from manifest's external dependencies"));
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
            args.flag("force"),
            true,  // Install py deps from requirements.txt
            args.flag("manifest-requirements"),
        );

        if (args.flag("ual"))
            foreach(dbname; project.databases.list())
                project.lodoo.addonsUpdateList(dbname);
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
            project.databases.list() : args.args("database");

        if (!dbnames)
            errorf("No databases specified.");

        foreach(db; dbnames) {
            infof("Updating list of addons for database %s", db);
            project.lodoo.addonsUpdateList(db);
        }
    }

}


/** Base command class for addons install/update/uninstall commands.
  * This class configures base options and provides unified method to parse
  * options and arguments responsible for searching addons
  **/
class CommandAddonsUpdateInstallUninstall: OdoodCommand {
    this(T...)(auto ref T args) {
        super(args);

        // Select databases to run command for
        this.add(
            new Option(
                "d", "db", "Database(s) to apply operation to."
            ).repeating());

        // Search for addons options
        this.add(new Option(
            null, "dir", "Directory to search for addons").repeating);
        this.add(new Option(
            null, "dir-r",
            "Directory to recursively search for addons").repeating);
        this.add(
            new Option(
                "f", "file",
                "Read addons names from file (addon names must be separated by new lines)"
            ).optional().repeating());
        this.add(new Option(
            null, "skip", "Skip addon specified by name.").repeating);
        this.add(new Option(
            null, "skip-re", "Skip addon specified by regex.").repeating);
        this.add(
            new Option(
                null, "skip-file",
                "Skip addons listed in specified file (addon names must be separated by new lines)"
            ).optional().repeating());
        this.add(new Argument(
            "addon", "Specify names of addons as arguments.").optional.repeating);

        // Other flags
        this.add(
            new Flag(
                null, "skip-errors", "Do not fail on errors during installation."));
    }

    /** Find addons to test
      **/
    protected auto findAddons(ProgramArgs args, in Project project) {
        string[] skip_addons = args.options("skip");
        auto skip_regexes = args.options("skip-re").map!(r => regex(r)).array;

        foreach(path; args.options("skip-file"))
            foreach(addon; project.addons.parseAddonsList(Path(path)))
                skip_addons ~= addon.name;

        OdooAddon[] addons;
        foreach(search_path; args.options("dir"))
            foreach(addon; project.addons.scan(Path(search_path), false)) {
                if (skip_addons.canFind(addon.name)) continue;
                if (skip_regexes.canFind!((re, addon) => !addon.matchFirst(re).empty)(addon.name)) continue;
                addons ~= addon;
            }

        foreach(search_path; args.options("dir-r"))
            foreach(addon; project.addons.scan(Path(search_path), true)) {
                if (skip_addons.canFind(addon.name)) continue;
                if (skip_regexes.canFind!((re, addon) => !addon.matchFirst(re).empty)(addon.name)) continue;
                addons ~= addon;
            }

        foreach(addon_name; args.args("addon")) {
            if (skip_addons.canFind(addon_name)) continue;
            if (skip_regexes.canFind!((re, addon) => !addon.matchFirst(re).empty)(addon_name)) continue;

            auto addon = project.addons(true).getByString(addon_name);
            enforce!OdoodCLIException(
                !addon.isNull,
                "Cannot find addon %s!".format(addon_name));
            addons ~= addon.get;
        }
        foreach(path; args.options("file")) {
            foreach(addon; project.addons.parseAddonsList(Path(path))) {
                if (skip_addons.canFind(addon.name)) continue;
                if (skip_regexes.canFind!((re, addon) => !addon.matchFirst(re).empty)(addon.name)) continue;
                addons ~= addon;
            }
        }

        return addons;
    }

    /** Apply delegate for each database
      **/
    protected auto applyForDatabases(ProgramArgs args, in Project project, void delegate (in string dbname) dg) {
        string[] dbnames = args.options("db") ?
            args.options("db") : project.databases.list();

        auto start_again=false;
        if (project.server.isRunning) {
            project.server.stop;
            start_again=true;
        }

        File log_file;
        if (project.odoo.logfile.exists)
            // Open file only if file exists
            log_file = project.odoo.logfile.openFile("rt");

        bool error = false;
        scope(exit) log_file.close();

        foreach(db; dbnames) {
            if (!log_file.isOpen && project.odoo.logfile.exists)
                // If file is not opened but exists, open it.
                // This is needed to correctly compute starting point
                // for tracking log messages happened during operation (dg)
                log_file.open(project.odoo.logfile.toString, "rt");

            auto log_start = log_file.isOpen ? log_file.size() : 0;

            try {
                // Try to apply delegate
                dg(db);
            } catch (ServerCommandFailedException e) {
                error = true;

                if (!log_file.isOpen && project.odoo.logfile.exists)
                    // If file is not opened but exists, open it.
                    // This is needed to be able to read log messages
                    // happeded during execution of dg delegate
                    log_file.open(project.odoo.logfile.toString, "rt");

                // Print errors from logfile to stdout.
                if (log_file.isOpen && log_file.size > log_start) {
                    writeln("Following errors detected during install:".red);
                    log_file.seek(log_start);
                    foreach(log_line; OdooLogProcessor(log_file))
                        if (log_line.isError)
                            printLogRecordSimplified(log_line);
                }
                if (!args.flag("skip-errors"))
                    throw new AddonsInstallUpdateUninstallFailed(
                        "Addon installation for database %s failed!".format(db));
            }
        }

        if (start_again)
            project.server.start;

        if (error)
            throw new AddonsInstallUpdateUninstallFailed(
                "Addon installation failed!");
    }
}

class CommandAddonsUpdate: CommandAddonsUpdateInstallUninstall {
    this() {
        super("update", "Update specified addons.");
        this.add(
            new Flag(
                null, "ual", "Update addons list before install.")),
        this.add(
            new Flag(
                "a", "all", "Update all modules"));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        applyForDatabases(args, project, (in string dbname) {
            if (args.flag("ual"))
                project.lodoo.addonsUpdateList(dbname, true);
            if (args.flag("all"))
                project.addons.updateAll(dbname);
            else
                project.addons.update(dbname, findAddons(args, project));
        });
    }

}


class CommandAddonsInstall: CommandAddonsUpdateInstallUninstall {
    this() {
        super("install", "Install specified addons.");
        this.add(
            new Flag(
                null, "ual", "Update addons list before install."));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        applyForDatabases(args, project, (in string dbname) {
            if (args.flag("ual"))
                project.lodoo.addonsUpdateList(dbname, true);
            project.addons.install(dbname, findAddons(args, project));
        });
    }
}


class CommandAddonsUninstall: CommandAddonsUpdateInstallUninstall {
    this() {
        super("uninstall", "Uninstall specified addons.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        applyForDatabases(args, project, (in string dbname) {
            project.addons.uninstall(dbname, findAddons(args, project));
        });
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
        this.add(new Flag(
            "r", "recursive",
            "Recursively process odoo_requirements.txt. " ~
            "If set, then Odood will automatically process " ~
            "odoo_requirements.txt file inside repositories mentioned in " ~
            "provided odoo_requirements.txt"));
        this.add(new Flag(
            null, "manifest-requirements",
            "Install python dependencies from manifest's external dependencies"));
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
                args.flag("single-branch"),
                args.flag("recursive"),
                true, // Install python deps from requirements.txt file if exists
                args.flag("manifest-requirements")
            );
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
        enforce!OdoodCLIException(
            !addon_n.isNull,
            "Cannot find addon %s".format(args.arg("addon")));
        auto addon = addon_n.get();

        foreach(dbname; project.databases.list)
            if (project.addons.isInstalled(dbname, addon))
                writeln(dbname);
    }
}


class CommandAddonsGeneratePyRequirements: OdoodCommand {
    this() {
        super(
            "generate-py-requirements",
            "Generate python's requirements.txt from addon's manifests. " ~
            "By default, it prints requirements to stdout.");
        this.add(new Option(
            "o", "out-file", "Path to file where to store generated requirements"));
        this.add(new Option(
            null, "dir",
            "Directory to search for addons to generate requirements.txt for.").repeating);
        this.add(new Option(
            null, "dir-r",
            "Directory to recursively search for addons to generate requirements.txt for.").repeating);
        this.add(new Argument(
            "addon", "Name of addon to generate manifest for.").repeating.optional);
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        Path output_path;
        bool print_to_file = false;
        if (args.option("out-file")) {
            output_path = Path(args.option("out-file"));
            print_to_file = true;
        }

        string[] dependencies;

        foreach(string search_path; args.options("dir"))
            foreach(addon; project.addons.scan(Path(search_path), false))
                foreach(dependency; addon.manifest.python_dependencies)
                    dependencies ~= dependency;

        foreach(string search_path; args.options("dir-r"))
            foreach(addon; project.addons.scan(Path(search_path), true))
                foreach(dependency; addon.manifest.python_dependencies)
                    dependencies ~= dependency;

        foreach(addon_name; args.args("addon")) {
            auto addon = project.addons.getByString(addon_name);
            if (!addon.isNull)
                foreach(dependency; addon.get.manifest.python_dependencies)
                    dependencies ~= dependency;
        }

        string requirements_content = dependencies.sort.uniq.join("\n") ~ "\n";
        if (print_to_file)
            output_path.writeFile(requirements_content);
        else
            writeln(requirements_content);
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
        this.add(new CommandAddonsGeneratePyRequirements());
    }
}

