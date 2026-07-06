module odood.cli.commands.addons;

private import std.stdio: writeln, writefln, File;
private import std.json: JSONValue;
private import std.logger;
private import std.format: format;
private import std.exception: enforce, basicExceptionCtors;
private import std.algorithm;
private import std.conv: to;
private import std.string: capitalize, strip, join;
private import std.regex;
private import std.array: array, empty;
private import std.typecons: Nullable;

private import thepath: Path;
private import darkcommand;
private import colored;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.cli.utils: printLogRecordSimplified, printJSON;
private import odood.lib.project: Project;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.addons.addon: OdooAddon;
private import odood.lib.odoo.log: OdooLogProcessor;
private import odood.lib.addons.manager:
    AddonsInstallUpdateException, AddonLocationSource, toKey;
private import odood.git: isGitRepo, GitRepository, GitURL;


/** This exception could be thrown when install/update/uninstall command failed.
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
    bool byPath;
    bool byName;
    bool byNameVersion;
    bool system;
    bool recursive;
    bool installable;
    bool notInstallable;
    bool linked;
    bool notLinked;
    bool withPrice;
    bool withoutPrice;
    bool assembly;
    bool table;
    bool json;
    string[] field;
    Nullable!string color;
    Nullable!Path path;

    this() {
        super("list", "List addons in specified directory.");
        this.addFlag!(byPath)("", "by-path", "Display addons by paths.");
        this.addFlag!(byName)("", "by-name", "Display addons by name (default).");
        this.addFlag!(byNameVersion)("", "by-name-version",
            "Display addon name with addon version");
        this.addFlag!(system)("s", "system", "Search for all addons available for Odoo.");
        this.addFlag!(recursive)("r", "recursive", "Search for addons recursively.");
        this.addFlag!(installable)("", "installable", "Filter only installable addons.");
        this.addFlag!(notInstallable)("", "not-installable",
            "Filter only not-installable addons.");
        this.addFlag!(linked)("", "linked", "Filter only linked addons.");
        this.addFlag!(notLinked)("", "not-linked",
            "Filter only addons that are not linked.");
        this.addFlag!(withPrice)("", "with-price",
            "Filter only addons that has price defined.");
        this.addFlag!(withoutPrice)("", "without-price",
            "Filter only addons that does not have price defined.");
        this.addFlag!(assembly)("", "assembly",
            "Show addons available in assembly");
        this.addFlag!(table)("t", "table", "Display list of addons as table");
        this.addFlag!(json)("", "json",
            "Output the addon catalog as JSON (name, path, version, source, " ~
            "repo, linked, installable). Honors the same filters.");
        this.addOption!(field)("f", "field",
            "Display field in table. Either a manifest field (e.g. version, " ~
            "author, license, summary, category, application, auto_install, " ~
            "installable, price, tags), or a computed field: " ~
            "'source' (odoo-core/custom-repo/downloads), 'repo' (owning " ~
            "repository), or 'linked' (whether linked into custom_addons).");
        this.addOption!(color)("c", "color",
            "Color output by selected scheme: " ~
            "link - color addons by link status, " ~
            "installable - color addons by installable state.");
        this.addArgument!(path)("path", "Path to search for addons in.")
            .acceptsDirectories();
    }

    private auto parseDisplayType() {
        if (byPath) return AddonDisplayType.by_path;
        if (byNameVersion) return AddonDisplayType.by_name_version;
        return AddonDisplayType.by_name;
    }

    private auto findAddons(in Project project) {
        enforce!OdoodCLIException(
            !assembly || project.assembly !is null,
            "No assembly configured for this project!");
        auto search_path = !path.isNull ?
            path.get :
            assembly ?
                project.assembly.raw.dist_dir :
                Path.current;

        OdooAddon[] addons;
        if (system) {
            info("Listing all addons available for Odoo");
            addons = project.addons.scan();
        } else {
            infof("Listing addons in %s", search_path.toString.yellow);
            addons = project.addons.scan(search_path, recursive);
        }

        return addons
            .sort!((a, b) => a.name < b.name)
            .filter!((addon) {
                if (installable && !addon.manifest.installable)
                    return false;
                if (notInstallable && addon.manifest.installable)
                    return false;
                if (linked && !project.addons.isLinked(addon))
                    return false;
                if (notLinked && project.addons.isLinked(addon))
                    return false;
                if (withPrice && !addon.manifest.price.is_set)
                    return false;
                if (withoutPrice && addon.manifest.price.is_set)
                    return false;
                return true;
            });
    }

    private string getAddonDisplayName(OdooAddon addon, in AddonDisplayType display_type) {
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
            in Project project,
            OdooAddon addon,
            in AddonDisplayType display_type) {

        auto addon_line = StyledString(getAddonDisplayName(addon, display_type));

        if (color.isNull)
            return addon_line;

        switch(color.get) {
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
                warningf("Unknown color option '%s'", color.get);
                break;
        }
        return addon_line;
    }

    private void displayAddonsList(in Project project) {
        auto display_type = parseDisplayType();
        foreach(addon; findAddons(project))
            writeln(getColoredAddonLine(project, addon, display_type));
    }

    private string[] prepareAddonsTableHeader(in string[] fields) {
        string[] header = ["Name".bold.to!string];
        foreach(f; fields)
            switch(f) {
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
                    header ~= [f.capitalize.bold.to!string];
                    break;
            }
        return header;
    }

    private string[] prepareAddonsTableRow(
            in string[] fields,
            in Project project,
            OdooAddon addon,
            in AddonDisplayType display_type) {
        string[] row = [
            getColoredAddonLine(project, addon, display_type).to!string,
        ];
        foreach(f; fields) {
            switch(f) {
                case "name":
                    row ~= [addon.manifest.name];
                    break;
                case "summary":
                    row ~= [addon.manifest.summary];
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
                case "source":
                    row ~= [project.addons.classifySource(addon.path).toKey];
                    break;
                case "repo": {
                    auto repo = project.addons.addonRepo(addon.path);
                    row ~= [
                        repo.isNull ? "" :
                            repo.get.relativeTo(
                                project.directories.repositories.realPath).toString,
                    ];
                    break;
                }
                case "linked":
                    row ~= [project.addons.isLinked(addon).to!string];
                    break;
                default:
                    throw new OdoodCLIException("Unknown field '%s'".format(f));
            }
        }
        return row;
    }

    private void displayAddonsTable(in Project project) {
        import tabletool;
        string[][] table_data;
        auto display_type = parseDisplayType();

        string[] fields = field.length > 0 ?
            field : ["version", "price", "installable"];

        table_data ~= prepareAddonsTableHeader(fields);

        foreach(addon; findAddons(project))
            table_data ~= prepareAddonsTableRow(fields, project, addon, display_type);
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

    private void displayAddonsJson(in Project project) {
        JSONValue[] addons;
        foreach(addon; findAddons(project)) {
            JSONValue j = JSONValue.emptyObject;
            j["name"] = addon.name;
            j["path"] = addon.path.toString;
            j["version"] = addon.manifest.module_version.toString;
            j["source"] = project.addons.classifySource(addon.path).toKey;
            auto repo = project.addons.addonRepo(addon.path);
            if (!repo.isNull)
                j["repo"] = repo.get.relativeTo(
                    project.directories.repositories.realPath).toString;
            j["linked"] = project.addons.isLinked(addon);
            j["installable"] = addon.manifest.installable;
            addons ~= j;
        }
        printJSON(JSONValue(addons));
    }

    override int execute() {
        auto project = Project.loadProject;

        if (json)
            displayAddonsJson(project);
        else if (table)
            displayAddonsTable(project);
        else
            displayAddonsList(project);
        return 0;
    }
}


class CommandAddonsLink: OdoodCommand {
    bool force;
    bool recursive;
    bool manifestRequirements;
    bool individualRequirements;
    bool withOdooRequirements;
    bool ual;
    Path path;

    this() {
        super("link", "Link addons in specified directory.");
        this.addFlag!(force)("f", "force", "Rewrite already linked/existing addon.");
        this.addFlag!(recursive)("r", "recursive",
            "Search for addons in this directory recursively.");
        this.addFlag!(manifestRequirements)("", "manifest-requirements",
            "Install python dependencies from manifest's external dependencies");
        this.addFlag!(individualRequirements)("", "individual-requirements",
            "Install Python requirements per-addon instead of batched");
        this.addFlag!(withOdooRequirements)("", "with-odoo-requirements",
            "Include Odoo's requirements.txt in the batch install");
        this.addFlag!(ual)("", "ual", "Update addons list for all databases");
        this.addArgument!(path)("path", "Path to search for addons in.")
            .acceptsDirectories();
    }

    override int execute() {
        auto project = Project.loadProject;

        project.addons.link(
            path,
            recursive,
            force,
            true,  // Install py deps from requirements.txt
            manifestRequirements,
            individualRequirements,
            withOdooRequirements,
        );

        if (ual)
            foreach(dbname; project.databases.list())
                project.lodoo.addonsUpdateList(dbname);
        return 0;
    }
}


class CommandAddonsUpdateList: OdoodCommand {
    string[] db;
    bool all;

    this() {
        super("update-list", "Update list of addons.");
        this.addFlag!(all)("a", "all", "Update all databases.");
        this.addArgument!(db)("database", "Database(s) to update addons list for.")
            .defaultValue([]);
    }

    override int execute() {
        auto project = Project.loadProject;

        string[] dbnames = all ? project.databases.list() : db;

        if (!dbnames)
            errorf("No databases specified.");

        foreach(dbname; dbnames) {
            infof("Updating list of addons for database %s", dbname);
            project.lodoo.addonsUpdateList(dbname);
        }
        return 0;
    }
}


/** Base command class for addons install/update/uninstall commands.
  **/
class CommandAddonsUpdateInstallUninstall: OdoodCommand {
    string[] db;
    Path[] dir;
    Path[] dirR;
    Path[] file;
    bool assembly;
    string[] skip;
    string[] skipRe;
    Path[] skipFile;
    bool skipErrors;
    bool ignoreUnfinishedUpdates;
    bool start;
    string[] addonNames;

    this(T...)(auto ref T args) {
        super(args);

        this.addOption!(db)("d", "db", "Database(s) to apply operation to.");
        this.addOption!(dir)("", "dir", "Directory to search for addons")
            .acceptsDirectories();
        this.addOption!(dirR)("", "dir-r",
            "Directory to recursively search for addons")
            .acceptsDirectories();
        this.addOption!(file)("f", "file",
            "Read addons names from file (addon names must be separated by new lines)")
            .acceptsFiles();
        this.addFlag!(assembly)("", "assembly",
            "Search for addons available in assembly");
        this.addOption!(skip)("", "skip", "Skip addon specified by name.");
        this.addOption!(skipRe)("", "skip-re", "Skip addon specified by regex.");
        this.addOption!(skipFile)("", "skip-file",
            "Skip addons listed in specified file (addon names must be separated by new lines)")
            .acceptsFiles();
        this.addFlag!(skipErrors)("", "skip-errors",
            "Do not fail on errors during installation.");
        this.addFlag!(ignoreUnfinishedUpdates)("", "ignore-unfinished-updates",
            "Do not fail if there are unfinished addon install/update/uninstall operations.");
        this.addFlag!(start)("", "start",
            "Start server after update (if everything is ok)");
        this.addArgument!(addonNames)("addon", "Names of addons to operate on.")
            .defaultValue([]);
    }

    protected void checkUnfinishedUpdates(in Project project, in string dbname) {
        auto unfinished = project.databases[dbname].getUnfinishedUpdates();
        if (unfinished.length == 0)
            return;
        warningf(
            "Database '%s' has %s unfinished install/update/uninstall operation(s): %s",
            dbname,
            unfinished.length,
            unfinished.map!(u => "%s (state=%s, available=%s)".format(
                u.addon_name, u.addon_state, u.is_available)).join(", "));
        if (!ignoreUnfinishedUpdates)
            throw new OdoodCLIException(
                "Database '%s' has unfinished addon operations. ".format(dbname) ~
                "Use --ignore-unfinished-updates to proceed anyway.");
    }

    protected auto findAddons(in Project project) {
        string[] skip_addons = skip;
        auto skip_regexes = skipRe.map!(r => regex(r)).array;

        foreach(path; skipFile)
            foreach(a; project.addons.parseAddonsList(path))
                skip_addons ~= a.name;

        OdooAddon[] addons;
        foreach(search_path; dir)
            foreach(a; project.addons.scan(search_path, false)) {
                if (skip_addons.canFind(a.name)) continue;
                if (skip_regexes.canFind!((re, name) => !name.matchFirst(re).empty)(a.name)) continue;
                addons ~= a;
            }

        foreach(search_path; dirR)
            foreach(a; project.addons.scan(search_path, true)) {
                if (skip_addons.canFind(a.name)) continue;
                if (skip_regexes.canFind!((re, name) => !name.matchFirst(re).empty)(a.name)) continue;
                addons ~= a;
            }

        foreach(addon_name; addonNames) {
            if (skip_addons.canFind(addon_name)) continue;
            if (skip_regexes.canFind!((re, name) => !name.matchFirst(re).empty)(addon_name)) continue;

            auto a = project.addons.getByString(addon_name);
            enforce!OdoodCLIException(
                !a.isNull,
                "Cannot find addon %s!".format(addon_name));
            addons ~= a.get;
        }
        foreach(path; file) {
            foreach(a; project.addons.parseAddonsList(path)) {
                if (skip_addons.canFind(a.name)) continue;
                if (skip_regexes.canFind!((re, name) => !name.matchFirst(re).empty)(a.name)) continue;
                addons ~= a;
            }
        }
        if (assembly) {
            enforce!OdoodCLIException(
                project.assembly !is null,
                "No assembly configured for this project!");
            foreach(a; project.addons.scan(path: project.assembly.raw.dist_dir, recursive: true)) {
                if (skip_addons.canFind(a.name)) continue;
                if (skip_regexes.canFind!((re, name) => !name.matchFirst(re).empty)(a.name)) continue;
                addons ~= a;
            }
        }

        return addons;
    }

    protected auto applyForDatabases(in Project project, void delegate (in string dbname) dg) {
        string[] dbnames = db.length > 0 ? db : project.databases.list();

        auto start_again = start;
        if (project.server.isRunning) {
            project.server.stop;
            start_again = true;
        }

        bool error = false;

        foreach(dbname; dbnames) {
            auto error_info = project.server.catchOdooErrors(() => dg(dbname));
            if (error_info.has_error) {
                error = true;
                if (error_info.log.length > 0)
                    writeln("Following errors detected during install/update/uninstall for database %s:".format(dbname.yellow).red);
                foreach(log_line; error_info.log)
                    printLogRecordSimplified(log_line);

                if (!skipErrors)
                    throw new AddonsInstallUpdateUninstallFailed(
                        "Addon installation for database %s failed!".format(dbname));
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
    bool ual;
    bool all;
    bool installedOnly;

    this() {
        super("update", "Update specified addons.");
        this.addFlag!(ual)("", "ual", "Update addons list before update.");
        this.addFlag!(all)("a", "all", "Update all modules");
        this.addFlag!(installedOnly)("", "installed-only",
            "Skip addons that are not installed in the database.");
    }

    override int execute() {
        auto project = Project.loadProject;

        applyForDatabases(project, (in string dbname) {
            checkUnfinishedUpdates(project, dbname);
            if (ual)
                project.lodoo.addonsUpdateList(dbname, true);
            if (all)
                project.addons.updateAll(dbname);
            else {
                auto addons = findAddons(project);
                if (installedOnly)
                    addons = addons
                        .filter!(a => project.addons.isInstalled(dbname, a))
                        .array;
                if (addons.empty)
                    infof("No installed addons to update in %s, skipping.", dbname);
                else
                    project.addons.update(dbname, addons);
            }
            checkUnfinishedUpdates(project, dbname);
        });
        return 0;
    }
}


class CommandAddonsInstall: CommandAddonsUpdateInstallUninstall {
    bool ual;
    bool missingOnly;

    this() {
        super("install", "Install specified addons.");
        this.addFlag!(ual)("", "ual", "Update addons list before install.");
        this.addFlag!(missingOnly)("", "missing-only",
            "Skip addons that are already installed in the database.");
    }

    override int execute() {
        auto project = Project.loadProject;

        applyForDatabases(project, (in string dbname) {
            checkUnfinishedUpdates(project, dbname);
            if (ual)
                project.lodoo.addonsUpdateList(dbname, true);
            auto addons = findAddons(project);
            if (missingOnly)
                addons = addons
                    .filter!(a => !project.addons.isInstalled(dbname, a))
                    .array;
            if (addons.empty)
                infof("All addons already installed in %s, skipping.", dbname);
            else
                project.addons.install(dbname, addons);
            checkUnfinishedUpdates(project, dbname);
        });
        return 0;
    }
}


class CommandAddonsUninstall: CommandAddonsUpdateInstallUninstall {
    this() {
        super("uninstall", "Uninstall specified addons.");
    }

    override int execute() {
        auto project = Project.loadProject;

        applyForDatabases(project, (in string dbname) {
            project.addons.uninstall(dbname, findAddons(project));
        });
        return 0;
    }
}


class CommandAddonsAdd: OdoodCommand {
    bool singleBranch;
    bool recursive;
    bool manifestRequirements;
    string[] odooApps;
    Path[] odooRequirements;

    this() {
        super("add", "Add addons to the project");
        this.addFlag!(singleBranch)("", "single-branch",
            "Clone repository with --single-branch options. " ~
            "This could significantly reduce size of data to be downloaded " ~
            "and increase performance.");
        this.addFlag!(recursive)("r", "recursive",
            "Recursively process odoo_requirements.txt. " ~
            "If set, then Odood will automatically process " ~
            "odoo_requirements.txt file inside repositories mentioned in " ~
            "provided odoo_requirements.txt");
        this.addFlag!(manifestRequirements)("", "manifest-requirements",
            "Install python dependencies from manifest's external dependencies");
        this.addOption!(odooApps)("", "odoo-apps", "Add addon from odoo apps.");
        this.addOption!(odooRequirements)("", "odoo-requirements",
            "Add modules (repos) from odoo_requirements.txt file (or directory " ~
            "containing odoo_requirements.txt), " ~
            "that is used by odoo-helper-scripts.")
            .acceptsPath();
    }

    override int execute() {
        auto project = Project.loadProject;

        foreach(app; odooApps)
            project.addons.downloadFromOdooApps(app);

        foreach(requirements_path; odooRequirements)
            project.addons.processOdooRequirements(
                requirements_path,
                singleBranch,
                recursive,
                true,
                manifestRequirements
            );
        return 0;
    }
}


class CommandAddonsIsInstalled: OdoodCommand {
    string addon;

    this() {
        super(
            "is-installed",
            "Print list of databases where specified addon is installed.");
        this.addArgument!(addon)("addon", "Name of addon or path to addon to check.");
    }

    override int execute() {
        auto project = Project.loadProject;

        auto addon_n = project.addons.getByString(addon);
        enforce!OdoodCLIException(
            !addon_n.isNull,
            "Cannot find addon %s".format(addon));
        auto a = addon_n.get();

        foreach(dbname; project.databases.list)
            if (project.addons.isInstalled(dbname, a))
                writeln(dbname);
        return 0;
    }
}


class CommandAddonsGeneratePyRequirements: OdoodCommand {
    Nullable!Path outFile;
    Path[] dir;
    Path[] dirR;
    string[] addon;

    this() {
        super(
            "generate-py-requirements",
            "Generate python's requirements.txt from addon's manifests. " ~
            "By default, it prints requirements to stdout.");
        this.addOption!(outFile)("o", "out-file",
            "Path to file where to store generated requirements");
        this.addOption!(dir)("", "dir",
            "Directory to search for addons to generate requirements.txt for.")
            .acceptsDirectories();
        this.addOption!(dirR)("", "dir-r",
            "Directory to recursively search for addons to generate requirements.txt for.")
            .acceptsDirectories();
        this.addArgument!(addon)("addon", "Name of addon to generate requirements for.")
            .defaultValue([]);
    }

    override int execute() {
        auto project = Project.loadProject;

        string[] dependencies;

        foreach(search_path; dir)
            foreach(a; project.addons.scan(search_path, false))
                foreach(dependency; a.manifest.python_dependencies)
                    dependencies ~= dependency;

        foreach(search_path; dirR)
            foreach(a; project.addons.scan(search_path, true))
                foreach(dependency; a.manifest.python_dependencies)
                    dependencies ~= dependency;

        foreach(addon_name; addon) {
            auto a = project.addons.getByString(addon_name);
            if (!a.isNull)
                foreach(dependency; a.get.manifest.python_dependencies)
                    dependencies ~= dependency;
        }

        string requirements_content = dependencies.sort.uniq.join("\n") ~ "\n";
        if (!outFile.isNull)
            outFile.get.writeFile(requirements_content);
        else
            writeln(requirements_content);
        return 0;
    }
}


class CommandAddonsFindInstalled: OdoodCommand {
    string[] db;
    Nullable!Path outFile;
    string format_ = "list";
    bool all;
    bool nonSystem;

    this() {
        super(
            "find-installed",
            "List addons installed in specified databases");
        this.addOption!(db)("d", "db", "Name of database to check for addons.");
        this.addOption!(outFile)("o", "out-file",
            "Path to file where to store result");
        this.addOption!(format_)("f", "format",
            "Output format. One of: list, assembly-spec. Default: list.")
            .defaultValue("list")
            .acceptsValues(["list", "assembly-spec"]);
        this.addFlag!(all)("a", "all", "Check all databases");
        this.addFlag!(nonSystem)("", "non-system",
            "List only custom addons, that are not default Odoo addons.");
    }

    auto findInstalledAddons(in Project project) {
        string[] dbnames = all ? project.databases.list() : db;

        string[] ignore_addon_names;
        if (nonSystem) {
            ignore_addon_names ~= project.addons.getSystemAddonsList().map!((a) => a.name).array;
        }

        string[] addon_names;
        foreach(dbname; dbnames) {
            auto db_conn = project.dbSQL(dbname);
            auto res = db_conn.runSQLQuery("SELECT array_agg(name) FROM ir_module_module WHERE state = 'installed'")[0][0].get!(string[]);
            addon_names ~= res.filter!(
                (aname) => !ignore_addon_names.canFind(aname) && !addon_names.canFind(aname)
            ).array;
        }
        return addon_names.sort.uniq;
    }

    string displayInstalledAddonsAsList(in Project project, in string[] addon_names) {
        return addon_names.join("\n") ~ "\n";
    }

    string displayInstalledAddonsAsAssemblySpec(in Project project, in string[] addon_names) {
        import std.array: appender;
        import odood.lib.assembly.spec;
        import dyaml;

        AssemblySpec spec;

        foreach(addon_name; addon_names) {
            auto maybeAddon = project.addons.getByName(addon_name);
            spec.addAddon(addon_name);

            if (maybeAddon.isNull)
                continue;

            auto addon = maybeAddon.get;

            if (!isGitRepo(addon.path))
                continue;

            auto repo = new GitRepository(addon.path);
            auto curr_branch = repo.getCurrBranch;
            spec.addSource(
                git_url: repo.getRemoteUrl,
                git_ref: curr_branch.isNull ? null : curr_branch.get,
            );
        }

        auto dumper = dyaml.dumper.dumper();
        dumper.defaultCollectionStyle = dyaml.style.CollectionStyle.block;

        auto output = appender!string();
        dumper.dump(output, spec.toYAML);

        return output[];
    }

    override int execute() {
        auto project = Project.loadProject;

        string[] addon_names = findInstalledAddons(project).array;

        string result;
        if (format_ == "list")
            result = displayInstalledAddonsAsList(project, addon_names);
        else if (format_ == "assembly-spec")
            result = displayInstalledAddonsAsAssemblySpec(project, addon_names);
        else
            assert(0, "Unsupported format %s".format(format_));

        if (!outFile.isNull)
            outFile.get.writeFile(result);
        else
            writeln(result);
        return 0;
    }
}


class CommandAddonsWhere: OdoodCommand {
    string addon;
    bool json;

    this() {
        super("where",
            "Show where an addon is located and whether it is available.");
        this.addFlag!(json)("", "json", "Output result in JSON format.");
        this.addArgument!(addon)("addon", "Name of the addon to locate.");
    }

    private string sourceLabel(in AddonLocationSource source) {
        final switch(source) {
            case AddonLocationSource.absent:     return "not found";
            case AddonLocationSource.odooCore:   return "Odoo core";
            case AddonLocationSource.customRepo: return "custom repository";
            case AddonLocationSource.downloads:  return "Odoo Apps download";
            case AddonLocationSource.other:      return "other addons path";
        }
    }

    override int execute() {
        auto project = Project.loadProject;
        auto loc = project.addons.locate(addon);

        if (json) {
            JSONValue j = JSONValue.emptyObject;
            j["name"] = loc.name;
            j["found"] = loc.found;
            j["source"] = loc.source.toKey;
            j["linked"] = loc.is_linked;
            if (loc.found) {
                j["path"] = loc.path.get.toString;
                j["installable"] = loc.is_installable;
                if (!loc.repo.isNull)
                    j["repo"] = loc.repo.get.toString;
            }
            printJSON(j);
            return loc.found ? 0 : 1;
        }

        if (!loc.found) {
            writefln("Addon '%s' not found.", addon);
            return 1;
        }

        writefln("Addon: %s", loc.name);
        writefln("  Source:      %s", sourceLabel(loc.source));
        writefln("  Path:        %s", loc.path.get);
        if (!loc.repo.isNull)
            writefln("  Repository:  %s", loc.repo.get);
        writefln("  Linked:      %s", loc.is_linked ? "yes" : "no");
        writefln("  Installable: %s", loc.is_installable ? "yes" : "no");
        return 0;
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
        this.add(new CommandAddonsFindInstalled());
        this.add(new CommandAddonsWhere());
    }
}
