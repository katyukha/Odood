module odood.cli.commands.assembly;

private import std.logger: infof, warningf;
private import std.json;
private import std.exception: enforce;
private import std.stdio: writefln, writeln;
private import std.array: empty, join, array;
private import std.format: format;
private import std.algorithm: map, canFind;
private import std.typecons: Nullable;

private import colored;
private import darkcommand;
private import thepath: Path;

private import odood.lib.assembly: Assembly, SourceUpgradeResult, ASSEMBLY_VERSION_PATH, ASSEMBLY_REQUIREMENTS_LOCK;
private import odood.lib.assembly.exception: OdoodAssemblyNothingToCommitException;
private import odood.lib.project: Project;
private import odood.utils.addons.addon: OdooAddon;
private import odood.git: parseGitURL, GitURL;
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
    Path path;

    this() {
        super("use", "Use (attach) assembly located at specified path. Mostly useful in CI flows.");
        this.addArgument!(path)("path", "Path to already existing assembly.")
            .acceptsDirectories();
    }

    override int execute() {
        auto assembly_path = path.toAbsolute;
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
            project.useAssembly(assemblyPath.get, save_config: false);
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
            project.useAssembly(assemblyPath.get, save_config: false);
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
        import std.datetime.stopwatch;

        auto project = loadProject();
        auto assembly = project.assembly;

        auto sw_total = StopWatch(AutoStart.yes);

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
            auto sw_db = StopWatch(AutoStart.yes);
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

            infof(
                "Assembly upgrade for database %s completed in %s.",
                db, sw_db.peek);
        }

        if (start_again)
            project.server.start;

        if (error)
            throw new OdoodCLIException("Assembly upgrade failed!");

        infof("Assembly upgrade completed in %s.", sw_total.peek);
        return 0;
    }
}


class CommandAssemblyUpgradeSources: AssemblyCommandBase {
    bool commit;
    Nullable!string commitMessage;
    Nullable!string commitUser;
    Nullable!string commitEmail;
    bool push;
    Nullable!string pushTo;

    this() {
        super("upgrade-sources", "Upgrade assembly source refs to the latest version tags on their remotes.");
        this.addFlag!(commit)("", "commit", "Commit the updated spec.");
        this.addOption!(commitMessage)("", "commit-message", "Commit message.");
        this.addOption!(commitUser)("", "commit-user", "Name of user to use for commit.");
        this.addOption!(commitEmail)("", "commit-email", "Email of user to use for commit.");
        this.addFlag!(push)("", "push", "Push changes after committing.");
        this.addOption!(pushTo)("", "push-to", "Name of branch to push changes to.");
    }

    override int execute() {
        auto project = loadProject;
        auto results = project.assembly.upgradeSourceRefs();

        bool any_changed = false;
        foreach(result; results) {
            if (result.changed) {
                writefln("  %-40s  %s  →  %s",
                    result.source_name,
                    result.old_ref.empty ? "(none)" : result.old_ref,
                    result.new_ref);
                any_changed = true;
            } else {
                writefln("  %-40s  %s (no change)",
                    result.source_name,
                    result.new_ref.empty ? "(none)" : result.new_ref);
            }
        }

        if (!any_changed) {
            writeln("All sources are already at the latest version.");
            return 0;
        }

        project.assembly.save();
        project.assembly.repo.add(project.assembly.spec_path);

        if (commit || push || !pushTo.isNull) {
            project.assembly.repo.commit(
                message: commitMessage.isNull ?
                    "[UPGRADE] Upgrade assembly source refs" : commitMessage.get,
                username: commitUser.isNull ? null : commitUser.get,
                useremail: commitEmail.isNull ? null : commitEmail.get);
        }

        if (push || !pushTo.isNull)
            project.assembly.push(
                branch_name: pushTo.isNull ? null : pushTo.get);

        return 0;
    }
}


class CommandAssemblyAddAddon: AssemblyCommandBase {
    string[] addons;
    Nullable!string source;
    bool odooApps;
    bool commit;
    Nullable!string commitMessage;
    Nullable!string commitUser;
    Nullable!string commitEmail;
    bool push;
    Nullable!string pushTo;

    this() {
        super("add-addon", "Add addon(s) to this assembly's spec.");
        this.addOption!(source)("", "source",
            "Bind the addon(s) to the named source in the spec.");
        this.addFlag!(odooApps)("", "odoo-apps",
            "Mark the addon(s) as downloaded from Odoo Apps.");
        this.addFlag!(commit)("", "commit", "Commit the updated spec.");
        this.addOption!(commitMessage)("", "commit-message", "Commit message.");
        this.addOption!(commitUser)("", "commit-user", "Name of user to use for commit.");
        this.addOption!(commitEmail)("", "commit-email", "Email of user to use for commit.");
        this.addFlag!(push)("", "push", "Push changes after committing.");
        this.addOption!(pushTo)("", "push-to", "Name of branch to push changes to.");
        this.addArgument!(addons)("addon", "Name(s) of addon(s) to add.")
            .defaultValue([]);
    }

    override int execute() {
        auto project = loadProject();
        auto assembly = project.assembly;

        enforce!OdoodCLIException(
            addons.length > 0,
            "At least one addon name must be specified.");
        enforce!OdoodCLIException(
            !(odooApps && !source.isNull),
            "Options --odoo-apps and --source are mutually exclusive.");

        // The named source must already exist in the spec.
        if (!source.isNull)
            enforce!OdoodCLIException(
                !assembly.spec.getSource(source.get).isNull,
                ("Assembly has no source named '%s'. " ~
                 "Add it first with 'odood assembly add-source'.").format(source.get));

        // Reject addons already present in the spec, and duplicates in the args.
        string[] seen;
        foreach(name; addons) {
            enforce!OdoodCLIException(
                !assembly.spec.hasAddon(name),
                "Addon '%s' is already present in the assembly spec.".format(name));
            enforce!OdoodCLIException(
                !seen.canFind(name),
                "Addon '%s' is specified more than once.".format(name));
            seen ~= name;
        }

        foreach(name; addons)
            assembly.addAddon(
                name: name,
                source_name: source.isNull ? null : source.get,
                from_odoo_apps: odooApps);

        assembly.save();
        assembly.repo.add(assembly.spec_path);
        infof("Added addon(s) to assembly spec: %s", addons.join(", "));

        if (commit || push || !pushTo.isNull)
            assembly.repo.commit(
                message: commitMessage.isNull ?
                    "[ASSEMBLY] Add addon(s): %s".format(addons.join(", ")) :
                    commitMessage.get,
                username: commitUser.isNull ? null : commitUser.get,
                useremail: commitEmail.isNull ? null : commitEmail.get);

        if (push || !pushTo.isNull)
            assembly.push(branch_name: pushTo.isNull ? null : pushTo.get);
        else if (!commit)
            infof("Run 'odood assembly sync' to fetch the new addon(s).");

        return 0;
    }
}


class CommandAssemblyAddSource: AssemblyCommandBase {
    Nullable!string url;
    Nullable!string github;
    Nullable!string oca;
    Nullable!string crnd;
    Nullable!string name;
    Nullable!string gitRef;
    bool commit;
    Nullable!string commitMessage;
    Nullable!string commitUser;
    Nullable!string commitEmail;
    bool push;
    Nullable!string pushTo;

    this() {
        super("add-source", "Add a git source to this assembly's spec.");
        this.addOption!(url)("", "url", "Git repository URL.");
        this.addOption!(github)("", "github",
            "GitHub repo as owner/repo (expands to https://github.com/owner/repo).");
        this.addOption!(oca)("", "oca",
            "OCA repo name (expands to https://github.com/oca/<repo>).");
        this.addOption!(crnd)("", "crnd",
            "CRND repo as group/repo (expands to ssh://git@gitlab.crnd.pro/group/repo).");
        this.addOption!(name)("", "name", "Name to reference this source by.");
        this.addOption!(gitRef)("", "ref", "Branch or tag to fetch.");
        this.addFlag!(commit)("", "commit", "Commit the updated spec.");
        this.addOption!(commitMessage)("", "commit-message", "Commit message.");
        this.addOption!(commitUser)("", "commit-user", "Name of user to use for commit.");
        this.addOption!(commitEmail)("", "commit-email", "Email of user to use for commit.");
        this.addFlag!(push)("", "push", "Push changes after committing.");
        this.addOption!(pushTo)("", "push-to", "Name of branch to push changes to.");
    }

    override int execute() {
        auto project = loadProject();
        auto assembly = project.assembly;

        // Exactly one of url/github/oca/crnd must be provided.
        string git_url;
        int provided = 0;
        if (!url.isNull)    { provided++; git_url = url.get; }
        if (!github.isNull) { provided++; git_url = "https://github.com/" ~ github.get; }
        if (!oca.isNull)    { provided++; git_url = "https://github.com/oca/" ~ oca.get; }
        if (!crnd.isNull)   { provided++; git_url = "ssh://git@gitlab.crnd.pro/" ~ crnd.get; }
        enforce!OdoodCLIException(
            provided == 1,
            "Exactly one of --url, --github, --oca, --crnd must be provided.");

        // A named source must be unique.
        if (!name.isNull)
            enforce!OdoodCLIException(
                assembly.spec.getSource(name.get).isNull,
                "Assembly already has a source named '%s'.".format(name.get));

        auto before = assembly.spec.sources.length;
        assembly.addSource(
            git_url: GitURL(git_url),
            name: name.isNull ? null : name.get,
            git_ref: gitRef.isNull ? null : gitRef.get);
        if (assembly.spec.sources.length == before) {
            warningf("Source %s is already present in the assembly spec; nothing to do.", git_url);
            return 0;
        }

        assembly.save();
        assembly.repo.add(assembly.spec_path);
        infof("Added source %s to assembly spec.", git_url);

        if (commit || push || !pushTo.isNull)
            assembly.repo.commit(
                message: commitMessage.isNull ?
                    "[ASSEMBLY] Add source: %s".format(git_url) : commitMessage.get,
                username: commitUser.isNull ? null : commitUser.get,
                useremail: commitEmail.isNull ? null : commitEmail.get);

        if (push || !pushTo.isNull)
            assembly.push(branch_name: pushTo.isNull ? null : pushTo.get);

        return 0;
    }
}


class CommandAssembly: OdoodCommand {
    Nullable!Path assemblyPath;

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
        this.add(new CommandAssemblyUpgradeSources());
        this.add(new CommandAssemblyAddAddon());
        this.add(new CommandAssemblyAddSource());
    }
}
