module odood.cli.commands.assembly;

private import std.logger: infof, warningf;
private import std.json;
private import std.exception: enforce;
private import std.stdio: writefln, writeln;
private import std.array: empty, join;
private import std.format: format;
private import std.algorithm: map;
private import std.typecons: Nullable;

private import colored;
private import darkcommand;
private import thepath: Path;

private import odood.lib.assembly: Assembly, ASSEMBLY_VERSION_PATH, ASSEMBLY_REQUIREMENTS_LOCK;
private import odood.lib.assembly.exception: OdoodAssemblyNothingToCommitException;
private import odood.lib.project: Project;
private import odood.utils.addons.addon: OdooAddon;
private import odood.git: parseGitURL;
private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.cli.utils: printLogRecordSimplified;


class CommandAssemblyInit: OdoodCommand {
    Nullable!string repo;

    this() {
        super("init", "Initialize assembly for this project");
        this.addOption!(repo)("", "repo",
            "Url to git repo with assembly to use for this project.");
    }

    override int execute() {
        auto project = Project.loadProject;
        enforce!OdoodCLIException(
            project.assembly is null,
            "Assembly already initialized!");
        if (repo.isNull)
            project.initializeAssembly();
        else {
            project.initializeAssembly(parseGitURL(repo.get));
            project.assembly.link();
        }
        return 0;
    }
}


class CommandAssemblyUse: OdoodCommand {
    string path;

    this() {
        super("use", "Use (attach) assembly located at specified path. Mostly useful in CI flows.");
        this.addArgument!(path)("path", "Path to already existing assembly.")
            .acceptsDirectories();
    }

    override int execute() {
        auto assembly_path = Path(path).toAbsolute;
        auto project = Project.loadProject;
        enforce!OdoodCLIException(
            project.assembly is null,
            "Project already has configured assembly!");
        project.useAssembly(assembly_path);
        return 0;
    }
}


class CommandAssemblyStatus: OdoodCommand {
    this() {
        super("status", "Project assembly status");
    }

    override int execute() {
        auto project = Project.loadProject;
        auto assemblyPath = parent!CommandAssembly.assemblyPath;
        if (!assemblyPath.isNull) {
            project.useAssembly(Path(assemblyPath.get), save_config: false);
        }
        if (project.assembly is null)
            writeln("There is no assembly configured for this project!");
        else {
            writefln(
                "Assembly: %s\nAddons: %s\nSources: %s\n",
                project.assembly.path,
                project.assembly.spec.addons.length,
                project.assembly.spec.sources.length,
            );
        }
        return 0;
    }
}


// Base class for assembly commands that need to load project with optional
// --assembly-path from the parent CommandAssembly.
class AssemblyCommandBase: OdoodCommand {

    this(T...)(auto ref T args) {
        super(args);
    }

    auto loadProject() {
        auto project = Project.loadProject;

        auto assemblyPath = parent!CommandAssembly.assemblyPath;
        if (!assemblyPath.isNull) {
            project.useAssembly(Path(assemblyPath.get), save_config: false);
        }
        enforce!OdoodCLIException(
            project.assembly !is null,
            "Assembly not initialized!");
        return project;
    }
}


class CommandAssemblySync: AssemblyCommandBase {
    bool commit;
    Nullable!string commitMessage;
    Nullable!string commitUser;
    Nullable!string commitEmail;
    bool failNothingToCommit;
    bool push;
    Nullable!string pushTo;
    bool changelog;
    bool dockerfile;
    bool generateLock;
    bool withOdooRequirements;

    this() {
        super("sync", "Synchronize assembly with updates from sources.");
        this.addFlag!(commit)("", "commit", "Commit changes.");
        this.addOption!(commitMessage)("", "commit-message", "Commit message");
        this.addOption!(commitUser)("", "commit-user", "Name of user to use for commit");
        this.addOption!(commitEmail)("", "commit-email", "Email of user to use for commit");
        this.addFlag!(failNothingToCommit)("", "fail-nothing-to-commit",
            "Fail (set exit code = 1) if there is nothing to commit");
        this.addFlag!(push)("", "push", "Automatically push changes if needed.");
        this.addOption!(pushTo)("", "push-to", "Name of branch to push changes to.");
        this.addFlag!(changelog)("", "changelog", "Generate changelog for assembly.");
        this.addFlag!(dockerfile)("", "dockerfile", "Generate Dockerfile for assembly.");
        this.addFlag!(generateLock)("", "generate-lock",
            "Generate requirements.lock.txt after syncing");
        this.addFlag!(withOdooRequirements)("", "with-odoo-requirements",
            "Include Odoo's requirements.txt when generating lock file");
    }

    override int execute() {
        auto project = loadProject();

        project.assembly.sync(
            generate_lock: generateLock,
            with_odoo_requirements: withOdooRequirements);

        if (changelog)
            project.assembly.generateChangelog;

        if (dockerfile)
            project.assembly.generateDockerfile;

        if (commit || push || !pushTo.isNull) {
            enforce!OdoodCLIException(
                project.assembly.repo.getChangedFiles(path_filters: [":(exclude)dist"], staged: false).length == 0,
                "Assembly Sync: There are unexpected changes in assembly. Please, handle it manually.");
            enforce!OdoodCLIException(
                project.assembly.repo.getChangedFiles(
                    path_filters: [
                        ":(exclude)dist",
                        ":(exclude)%s".format(ASSEMBLY_VERSION_PATH),
                        ":(exclude)%s".format(ASSEMBLY_REQUIREMENTS_LOCK),
                        ":(exclude)CHANGELOG.md",
                        ":(exclude)CHANGELOG.latest.md",
                        ":(exclude)Dockerfile",
                        ":(exclude).dockerignore",
                    ],
                    staged: true
                ).length == 0,
                "Assembly Sync: There are unexpected staged changes in assembly. Please, handle it manually.");

            if (
                project.assembly.repo.getChangedFiles(
                    path_filters: [
                        "dist",
                        "%s".format(ASSEMBLY_VERSION_PATH),
                        "%s".format(ASSEMBLY_REQUIREMENTS_LOCK),
                        "Dockerfile",
                        ".dockerignore",
                    ],
                    staged: true)
            ) {
                infof("Assembly Sync: Committing assembly changes...");
                project.assembly.repo.commit(
                    message: commitMessage.isNull ?
                        "[SYNC] Assembly synced" : commitMessage.get,
                    username: commitUser.isNull ? null : commitUser.get,
                    useremail: commitEmail.isNull ? null : commitEmail.get);
            } else {
                warningf("Assembly Sync: There is no changes to be committed!");
                if (failNothingToCommit)
                    exitWith(1);
                else
                    return 0;
            }
        }

        if (push || !pushTo.isNull)
            project.assembly.push(
                branch_name: pushTo.isNull ? null : pushTo.get);
        return 0;
    }
}


class CommandAssemblyLink: AssemblyCommandBase {
    bool manifestRequirements;
    bool individualRequirements;
    bool withOdooRequirements;
    bool ual;

    this() {
        super("link", "Link addons from this assembly to custom addons");
        this.addFlag!(manifestRequirements)("", "manifest-requirements",
            "Install python dependencies from manifest's external dependencies");
        this.addFlag!(individualRequirements)("", "individual-requirements",
            "Install Python requirements per-addon instead of batched");
        this.addFlag!(withOdooRequirements)("", "with-odoo-requirements",
            "Include Odoo's requirements.txt in the batch install");
        this.addFlag!(ual)("", "ual", "Update addons list for all databases");
    }

    override int execute() {
        auto project = loadProject();
        project.assembly.link(
            manifest_requirements: manifestRequirements,
            individual_requirements: individualRequirements,
            with_odoo_requirements: withOdooRequirements,
        );
        if (ual)
            foreach(dbname; project.databases.list())
                project.lodoo.addonsUpdateList(dbname);
        return 0;
    }
}


class CommandAssemblyPull: AssemblyCommandBase {
    bool link;

    this() {
        super("pull", "Pull updates for this assembly.");
        this.addFlag!(link)("", "link", "Relink addons in this assembly after pull");
    }

    override int execute() {
        auto project = loadProject();
        auto assembly = project.assembly;

        assembly.pull;

        if (link)
            assembly.link();
        return 0;
    }
}


class CommandAssemblyUpgrade: AssemblyCommandBase {
    bool backup;
    bool skipErrors;
    bool start;

    this() {
        super("upgrade", "Upgrade assembly (optionally do backup, pull changes, update addons).");
        this.addFlag!(backup)("", "backup", "Do backup of all databases");
        this.addFlag!(skipErrors)("", "skip-errors",
            "Continue upgrade next databases if upgrade of db had error.");
        this.addFlag!(start)("", "start",
            "Start the server if upgrade completed successfully and server was not running before upgrade.");
    }

    override int execute() {
        auto project = loadProject();
        auto assembly = project.assembly;

        if (backup)
            foreach(db; project.databases.list)
                project.databases.backup(db);

        assembly.pull;
        assembly.link();

        auto start_again = start;
        if (project.server.isRunning) {
            project.server.stop;
            start_again = true;
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

                if (!skipErrors)
                    throw new OdoodCLIException(
                        "Assembly upgrade for database %s failed!!".format(db));
            }
        }

        if (start_again)
            project.server.start;

        if (error)
            throw new OdoodCLIException("Assembly upgrade failed!");
        return 0;
    }
}


class CommandAssembly: OdoodCommand {
    Nullable!string assemblyPath;

    this() {
        super("assembly", "Manage assembly of this project");
        this.addOption!(assemblyPath)("p", "assembly-path",
            "Path to assembly directory.")
            .acceptsDirectories();

        this.add(new CommandAssemblyInit());
        this.add(new CommandAssemblyUse());
        this.add(new CommandAssemblyStatus());
        this.add(new CommandAssemblySync());
        this.add(new CommandAssemblyLink());
        this.add(new CommandAssemblyPull());
        this.add(new CommandAssemblyUpgrade());
    }
}
