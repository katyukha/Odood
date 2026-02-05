module odood.cli.commands.assembly;

private import std.logger: infof, warningf;
private import std.json;
private import std.exception: enforce;
private import std.stdio: writefln, writeln;
private import std.array: empty, join;
private import std.format: format;
private import std.algorithm: map;

private import colored;
private import commandr: Argument, Option, Flag, ProgramArgs;
private import thepath: Path;

private import odood.lib.assembly: Assembly, ASSEMBLY_VERSION_PATH;
private import odood.lib.assembly.exception: OdoodAssemblyNothingToCommitException;
private import odood.lib.project: Project;
private import odood.utils.addons.addon: OdooAddon;
private import odood.git: parseGitURL;
private import odood.cli.core: OdoodCommand, OdoodCLIException, OdoodCLIExitException;
private import odood.cli.utils: printLogRecordSimplified;


class CommandAssemblyInit: OdoodCommand {
    this() {
        super("init", "Initialize assembly for this project");
        this.add(new Option(
            null, "repo", "Url to git repo with assembly to use for this project."));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        enforce!OdoodCLIException(
            project.assembly.isNull,
            "Assembly already initialized!");
        if (args.option("repo").empty)
            project.initializeAssembly();
        else
            project.initializeAssembly(parseGitURL(args.option("repo")));
            project.assembly.get.link();
    }
}


class CommandAssemblyUse: OdoodCommand {
    this() {
        super("use", "Use (attach) assembly located at specified path. Mostly useful in CI flows.");
        this.add(new Argument(
            "path", "Path to already existing assembly."));
    }

    public override void execute(ProgramArgs args) {
        auto path = Path(args.arg("path")).toAbsolute;
        auto project = Project.loadProject;
        enforce!OdoodCLIException(
            project.assembly.isNull,
            "Project already has configured assembly!");
        project.useAssembly(path);
    }
}


class CommandAssemblyStatus: OdoodCommand {
    this() {
        super("status", "Project assembly status");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        if (args.parent.option("assembly-path")) {
            auto assembly_path = Path(args.parent.option("assembly-path"));
            project.useAssembly(assembly_path, save_config: false);
        }
        if (project.assembly.isNull)
            writeln("There is no assembly configured for this project!");
        else {
            writefln(
                "Assembly: %s\nAddons: %s\nSources: %s\n",
                project.assembly.get.path,
                project.assembly.get.spec.addons.length,
                project.assembly.get.spec.sources.length,
            );
        }
    }
}

// Base class for assembly command, that could be used to load project
// And optionally handle --assembly-path option in parent command
class AssemblyCommandBase: OdoodCommand {

    this(T...)(auto ref T args) {
        super(args);
    }

    auto loadProject(ProgramArgs args) {
        auto project = Project.loadProject;

        if (args.parent.option("assembly-path")) {
            auto assembly_path = Path(args.parent.option("assembly-path"));
            project.useAssembly(assembly_path, save_config: false);
        }
        enforce!OdoodCLIException(
            !project.assembly.isNull,
            "Assembly not initialized!");
        return project;
    }
}


class CommandAssemblySync: AssemblyCommandBase {
    this() {
        super("sync", "Synchronize assembly with updates from sources.");
        this.add(new Flag(
            null, "commit", "Commit changes."));
        this.add(new Option(
            null, "commit-message", "Commit message"));
        this.add(new Option(
            null, "commit-user", "Name of user to use for commit"));
        this.add(new Option(
            null, "commit-email", "Email of user to use for commit"));
        this.add(new Flag(
            null, "fail-nothing-to-commit", "Fail (set exit code = 1) if there is nothing to commit"));
        this.add(new Flag(
            null, "push", "Automatically push changes if needed."));
        this.add(new Option(
            null, "push-to", "Name of branch to push changes to."));
        this.add(new Flag(
            null, "changelog", "Generate changelog for assembly."));
        this.add(new Flag(
            null, "dockerfile", "Generate Dockerfile for assembly."));
    }

    public override void execute(ProgramArgs args) {
        auto project = loadProject(args);

        // Do the sync
        project.assembly.get.sync();

        if (args.flag("changelog"))
            project.assembly.get.generateChangelog;

        if (args.flag("dockerfile"))
            project.assembly.get.generateDockerfile;

        // Commit changes if requested (usually useful in CI flows)
        if (args.flag("commit") || args.flag("push") || args.option("push-to")) {
            enforce!OdoodCLIException(
                project.assembly.get.repo.getChangedFiles(path_filters: [":(exclude)dist"], staged: false).length == 0,
                "Assembly Sync: There are unexpected changes in assembly. Please, handle it manually.");
            enforce!OdoodCLIException(
                project.assembly.get.repo.getChangedFiles(
                    path_filters: [
                        ":(exclude)dist",
                        ":(exclude)%s".format(ASSEMBLY_VERSION_PATH),
                        ":(exclude)CHANGELOG.md",
                        ":(exclude)CHANGELOG.latest.md",
                        ":(exclude)Dockerfile",
                        ":(exclude).dockerignore",
                    ],
                    staged: true
                ).length == 0,
                "Assembly Sync: There are unexpected staged changes in assembly. Please, handle it manually.");

            if (
                project.assembly.get.repo.getChangedFiles(
                    // Changes that have to be commited (expected changes with changelog excluded)
                    path_filters: [
                        "dist",
                        "%s".format(ASSEMBLY_VERSION_PATH),
                        "Dockerfile",
                        ".dockerignore",
                    ],
                    staged: true)
            ) {
                infof("Assembly Sync: Commiting assembly changes...");
                project.assembly.get.repo.commit(
                    message: args.option("commit-message") ? args.option("commit-message") : "[SYNC] Assembly synced",
                    username: args.option("commit-user"),
                    useremail: args.option("commit-email"));
            } else {
                warningf("Assembly Sync: There is no changes to be committed!");
                if (args.flag("fail-nothing-to-commit"))
                    throw new OdoodCLIExitException(1);
                else
                    return;  // Nothing to commit, so no further processing needed
            }
        }

        // Push changes back
        if (args.flag("push") || args.option("push-to"))
            project.assembly.get.push(branch_name: args.option("push-to").empty ? null : args.option("push-to"));
    }
}

class CommandAssemblyLink: AssemblyCommandBase {
    this() {
        super("link", "Link addons from this assembly to custom addons");
        this.add(new Flag(
            null, "manifest-requirements",
            "Install python dependencies from manifest's external dependencies"));
        this.add(new Flag(
            null, "ual", "Update addons list for all databases"));
    }

    public override void execute(ProgramArgs args) {
        auto project = loadProject(args);
        project.assembly.get.link(
            manifest_requirements: args.flag("manifest-requirements"),
        );
        if (args.flag("ual"))
            foreach(dbname; project.databases.list())
                project.lodoo.addonsUpdateList(dbname);
    }
}


class CommandAssemblyPull: AssemblyCommandBase {
    this() {
        super("pull", "Pull updates for this assembly.");
        this.add(new Flag(
            null, "link",
            "Relink addons in this assembly after pull"));
    }

    public override void execute(ProgramArgs args) {
        auto project = loadProject(args);
        auto assembly = project.assembly.get;

        assembly.pull;

        if (args.flag("link") || args.flag("update-addons"))
            assembly.link();
    }
}


class CommandAssemblyUpgrade: AssemblyCommandBase {
    this() {
        super("upgrade", "Upgrade assembly (optionally do backup, pull changes, update addons).");
        this.add(new Flag(
            null, "backup",
            "Do backup of all databases"));
        this.add(new Flag(
            null, "skip-errors", "Continue upgrade next databases if upgrade of db had error."));
        this.add(new Flag(
            null, "start", "Start the server if upgrade completed successfully and server was not running before upgrade."));
    }

    public override void execute(ProgramArgs args) {
        auto project = loadProject(args);
        auto assembly = project.assembly.get;

        if (args.flag("backup"))
            foreach(db; project.databases.list)
                project.databases.backup(db);

        assembly.pull;
        assembly.link();

        auto start_again = args.flag("start");
        if (project.server.isRunning) {
            project.server.stop;
            start_again=true;
        }

        bool error = false;
        OdooAddon[] addons = project.addons.scan(assembly.dist_dir, recursive: false);
        foreach(db; project.databases.list) {
            auto error_info = project.server.catchOdooErrors(() {
                project.lodoo.addonsUpdateList(
                    dbname: db,
                    ignore_error: true
                );
                project.addons.update(db, addons);
            });

            auto unfinished_updates = project.databases[db].getUnfinishedUpdates();
            if (unfinished_updates.length > 0) {
                warningf(
                    "db (%s) - there are unfinished install/update/uninstall of " ~
                    "following addons: %s",
                    db, unfinished_updates.map!((line) {
                        return "%s (state=%s, is_available=%s)".format(
                            line.addon_name, line.addon_state, line.is_available
                        );
                    }).join(", "));
            }

            if (error_info.has_error) {
                error = true;
                writeln("Following errors detected during assembly addons update for database %s:".format(db.yellow).red);
                foreach(log_line; error_info.log)
                    printLogRecordSimplified(log_line);

                if (!args.flag("skip-errors"))
                    throw new OdoodCLIException(
                        "Assembly upgrade for database %s failed!!".format(db));
            }
        }

        if (start_again)
            project.server.start;

        if (error)
            throw new OdoodCLIException("Assembly upgrade failed!");
    }
}


class CommandAssembly: OdoodCommand {
    this() {
        super("assembly", "Manage assembly of this project");
        this.add(new Option(
            "p", "assembly-path", "Path to assembly directory."));

        this.add(new CommandAssemblyInit());
        this.add(new CommandAssemblyUse());
        this.add(new CommandAssemblyStatus());
        this.add(new CommandAssemblySync());
        this.add(new CommandAssemblyLink());
        this.add(new CommandAssemblyPull());
        this.add(new CommandAssemblyUpgrade());
    }
}


