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

private import odood.lib.assembly: Assembly, SourceUpgradeResult, ASSEMBLY_VERSION_PATH, ASSEMBLY_REQUIREMENTS_LOCK, ASSEMBLY_ADDONS_MD_PATH, ASSEMBLY_ADDONS_CSV_PATH;
private import odood.lib.assembly.exception: OdoodAssemblyNothingToCommitException;
private import odood.lib.addons.repository: renderChangelog;
private import odood.project: Project;
private import odood.utils.addons.addon: OdooAddon;
private import odood.git: parseGitURL, GitURL;
private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.cli.utils: printLogRecordSimplified;


/* Files the sync and release commands generate themselves. Anything else being
 * dirty means the working tree holds changes the command did not make, which
 * have to be handled by hand. */
private string[] assemblyGeneratedPaths() {
    return [
        ASSEMBLY_VERSION_PATH.toString,
        ASSEMBLY_REQUIREMENTS_LOCK.toString,
        ASSEMBLY_ADDONS_MD_PATH.toString,
        ASSEMBLY_ADDONS_CSV_PATH.toString,
        "CHANGELOG.md",
        "CHANGELOG.latest.md",
        "Dockerfile",
        ".dockerignore",
    ];
}

/// The same paths as `:(exclude)` pathspecs, plus any extra paths to exclude.
private string[] assemblyGeneratedExcludes(in string[] extra...) {
    return (assemblyGeneratedPaths ~ extra.dup)
        .map!(pth => ":(exclude)%s".format(pth))
        .array;
}


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
            auto current = project.assembly.raw.currentVersion(include_remote: false);
            writefln(
                "Assembly: %s\nVersion: %s\nAddons: %s\nSources: %s\n",
                project.assembly.raw.path,
                current.isNull ? "not released yet" : current.get.toString,
                project.assembly.raw.spec.addons.length,
                project.assembly.raw.spec.sources.length,
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
    bool addonsListMd;
    bool addonsListCsv;
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
        this.addFlag!(changelog)("", "changelog",
            "Removed: changelog generation and version bumping moved to "
            ~ "'odood assembly release'.");
        this.addFlag!(dockerfile)("", "dockerfile", "Generate Dockerfile for assembly.");
        this.addFlag!(addonsListMd)("", "addons-list-md", "Generate ADDONS.md for assembly.");
        this.addFlag!(addonsListCsv)("", "addons-list-csv", "Generate ADDONS.csv for assembly.");
        this.addFlag!(generateLock)("", "generate-lock",
            "Generate requirements.lock.txt after syncing");
        this.addFlag!(withOdooRequirements)("", "with-odoo-requirements",
            "Include Odoo's requirements.txt when generating lock file");
    }

    override int execute() {
        /* Sync cannot assign a version: it runs where no tag can exist yet, so
         * two branches off the same point would claim the same number. */
        enforce!OdoodCLIException(
            !changelog,
            "'odood assembly sync --changelog' has been removed: generating a "
            ~ "changelog means assigning a version, which is now done by "
            ~ "'odood assembly release'. Drop --changelog here and add a "
            ~ "'odood assembly release' step after the sync.");

        auto project = loadProject();

        project.assembly.sync(
            generate_lock: generateLock,
            with_odoo_requirements: withOdooRequirements);

        if (dockerfile)
            project.assembly.raw.generateDockerfile;

        if (addonsListMd || addonsListCsv)
            project.assembly.raw.generateAddonsList(
                md: addonsListMd, csv: addonsListCsv);

        if (commit || push || !pushTo.isNull) {
            enforce!OdoodCLIException(
                project.assembly.raw.repo.getChangedFiles(path_filters: [":(exclude)dist"], staged: false).length == 0,
                "Assembly Sync: There are unexpected changes in assembly. Please, handle it manually.");
            enforce!OdoodCLIException(
                project.assembly.raw.repo.getChangedFiles(
                    path_filters: assemblyGeneratedExcludes("dist"),
                    staged: true
                ).length == 0,
                "Assembly Sync: There are unexpected staged changes in assembly. Please, handle it manually.");

            if (
                project.assembly.raw.repo.getChangedFiles(
                    path_filters: assemblyGeneratedPaths ~ "dist",
                    staged: true)
            ) {
                infof("Assembly Sync: Committing assembly changes...");
                project.assembly.raw.repo.commit(
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
            project.assembly.raw.push(
                branch_name: pushTo.isNull ? null : pushTo.get);
        return 0;
    }
}


class CommandAssemblyRelease: AssemblyCommandBase {
    bool failNothingToRelease;
    bool push;
    bool dryRun;
    bool changelog;
    bool versionFile;
    bool dockerfile;
    bool addonsListMd;
    bool addonsListCsv;
    Nullable!string baseRef;
    Nullable!string commitMessage;
    Nullable!string commitUser;
    Nullable!string commitEmail;

    this() {
        super("release",
            "Release the assembly: auto-version, tag, and optionally push.");
        this.addFlag!(failNothingToRelease)("", "fail-nothing-to-release",
            "Exit with code 1 when no changes are detected since the last release.");
        this.addFlag!(push)("", "push", "Push the release commit and tag to origin.");
        this.addFlag!(dryRun)("n", "dry-run",
            "Only show what would be released; do not write, commit, tag or push.");
        this.addFlag!(changelog)("", "changelog",
            "Generate CHANGELOG.md and CHANGELOG.latest.md for this release.");
        this.addFlag!(versionFile)("", "version-file",
            "Create the VERSION file even if the assembly does not have one. "
            ~ "An existing VERSION file is always updated.");
        this.addFlag!(dockerfile)("", "dockerfile",
            "Regenerate the Dockerfile so its version label matches this release.");
        this.addFlag!(addonsListMd)("", "addons-list-md", "Generate ADDONS.md.");
        this.addFlag!(addonsListCsv)("", "addons-list-csv", "Generate ADDONS.csv.");
        this.addOption!(baseRef)("", "base-ref",
            "Compare against this revision instead of the latest release tag.");
        this.addOption!(commitMessage)("", "commit-message",
            "Commit message for the release commit (default: 'Release <version>').");
        this.addOption!(commitUser)("", "commit-user",
            "Git author name for the release commit.");
        this.addOption!(commitEmail)("", "commit-email",
            "Git author email for the release commit.");
    }

    override int execute() {
        auto project = loadProject();
        auto assembly = project.assembly.raw;
        auto repo = assembly.repo;
        immutable serie_str = project.odoo.serie.toString;

        auto current_branch = repo.getCurrBranch();
        immutable on_stable =
            !current_branch.isNull && current_branch.get == serie_str;

        if (push) {
            enforce!OdoodCLIException(
                !current_branch.isNull,
                "Cannot push a release from a detached HEAD.");
            enforce!OdoodCLIException(
                on_stable,
                ("Releases with --push must be made from branch '%s'. "
                ~ "Current: %s.").format(serie_str, current_branch.get));
            enforce!OdoodCLIException(
                repo.hasRemoteUrl("origin"),
                "Cannot push: no 'origin' remote is configured.");
        } else if (!on_stable) {
            warningf(
                "Assembly Release: releasing from '%s', not the stable branch '%s'.",
                current_branch.isNull ? "detached HEAD" : current_branch.get,
                serie_str);
        }

        if (repo.hasRemoteUrl("origin")) {
            repo.fetchOrigin(serie_str);

            /* Version resolution merges local and remote tags, and falls back
             * to local-only with a warning when the remote cannot be listed.
             * That fallback is fine for a local release but not for a pushed
             * one: a stale answer would create a duplicate tag on origin. */
            if (push)
                repo.listRemoteTags("origin");

            immutable remote_ref = "origin/" ~ serie_str;
            if (on_stable
                    && repo.tryRevParse(remote_ref).length > 0
                    && !repo.isAncestor(remote_ref, "HEAD")) {
                enforce!OdoodCLIException(
                    !push,
                    ("Local branch '%s' is behind '%s'. "
                    ~ "Pull the latest changes before releasing with --push.").format(
                        serie_str, remote_ref));
                warningf(
                    "Assembly Release: local '%s' does not include the latest "
                    ~ "commits from '%s'. The release will not cover them.",
                    serie_str, remote_ref);
            }
        }

        /* The release commit is a plain `git commit`, so it takes whatever is
         * in the index. Requiring a clean tree is what keeps the tagged tree
         * to exactly the content the version was computed from. */
        if (!dryRun)
            enforce!OdoodCLIException(
                repo.getChangedFiles(staged: false).length == 0
                && repo.getChangedFiles(staged: true).length == 0,
                "Assembly Release: the assembly has uncommitted changes. "
                ~ "Commit them (for example with 'odood assembly sync --commit') "
                ~ "or stash them before releasing.");

        /* A previous run may have tagged and then failed to push. Detect that
         * before computing a release: the bump is measured from the latest tag,
         * so an unpushed tag at HEAD makes the next run find no changes and
         * report success without ever pushing it. */
        auto head_tag = assembly.releasedAtHead;
        if (!head_tag.isNull) {
            infof("Assembly Release: HEAD is already released as %s.",
                head_tag.get);
            if (!dryRun && push) {
                repo.push();
                repo.pushTag(head_tag.get.toString);
                infof("Assembly Release: pushed branch and tag to origin.");
            }
            return 0;
        }

        auto result = assembly.prepareRelease(
            base_rev: baseRef.isNull ? null : baseRef.get);

        if (result.isNull) {
            infof("Assembly Release: nothing to release, no changes detected.");
            if (failNothingToRelease)
                exitWith(1);
            return 0;
        }

        immutable tag_name = result.get.new_version.toString;

        /* generateChangelog restores CHANGELOG.md from the base ref before
         * prepending, so a base older than the last release would drop every
         * section written since. */
        if (changelog && !baseRef.isNull) {
            auto latest = assembly.currentVersion;
            enforce!OdoodCLIException(
                latest.isNull
                || !repo.isAncestor(baseRef.get, latest.get.toString)
                || repo.tryRevParse(baseRef.get)
                    == repo.tryRevParse(latest.get.toString),
                ("--base-ref '%s' is older than the latest release (%s). "
                ~ "Generating a changelog from it would discard the entries "
                ~ "written since. Use a later base, or drop --changelog.").format(
                    baseRef.get, latest.isNull ? "none" : latest.get.toString));
        }

        if (dryRun) {
            infof("Assembly Release: would release version %s.", tag_name);
            if (changelog) {
                infof("Changelog preview:");
                writeln(renderChangelog(result.get.addon_changes));
            }
            return 0;
        }

        /* All generated artifacts go into one commit before the tag, so the tag
         * points at a tree that already contains them. generate* only write and
         * stage; committing is up to us. */
        if (changelog)
            assembly.generateChangelog(result.get);
        assembly.generateVersionFile(result.get.new_version, create: versionFile);
        if (dockerfile)
            assembly.generateDockerfile(tag_name);
        if (addonsListMd || addonsListCsv)
            assembly.generateAddonsList(md: addonsListMd, csv: addonsListCsv);

        if (repo.getChangedFiles(
                path_filters: assemblyGeneratedPaths, staged: true).length > 0) {
            repo.commit(
                message: commitMessage.isNull
                    ? "Release %s".format(tag_name) : commitMessage.get,
                username: commitUser.isNull ? null : commitUser.get,
                useremail: commitEmail.isNull ? null : commitEmail.get);
            infof("Assembly Release: release artifacts committed.");
        }

        enforce!OdoodCLIException(
            !repo.listLocalTags().canFind(tag_name),
            ("Tag %s already exists and points at another commit. "
            ~ "Fetch the latest changes and re-run.").format(tag_name));
        repo.setTag(tag_name);
        infof("Assembly Release: created tag %s.", tag_name);

        if (push) {
            repo.push();
            repo.pushTag(tag_name);
            infof("Assembly Release: pushed branch and tag to origin.");
        }
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

        assembly.raw.pull;

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

        assembly.raw.pull;
        assembly.link();

        auto start_again = start;
        if (project.server.isRunning) {
            project.server.stop;
            start_again = true;
        }

        bool error = false;
        OdooAddon[] addons = project.addons.scan(assembly.raw.dist_dir, recursive: false);
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
        auto results = project.assembly.raw.upgradeSourceRefs();

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

        project.assembly.raw.save();
        project.assembly.raw.repo.add(project.assembly.raw.spec_path);

        if (commit || push || !pushTo.isNull) {
            project.assembly.raw.repo.commit(
                message: commitMessage.isNull ?
                    "[UPGRADE] Upgrade assembly source refs" : commitMessage.get,
                username: commitUser.isNull ? null : commitUser.get,
                useremail: commitEmail.isNull ? null : commitEmail.get);
        }

        if (push || !pushTo.isNull)
            project.assembly.raw.push(
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
                !assembly.raw.spec.getSource(source.get).isNull,
                ("Assembly has no source named '%s'. " ~
                 "Add it first with 'odood assembly add-source'.").format(source.get));

        // Skip addons already present in the spec (or duplicated in the args),
        // warning about each rather than failing the whole command.
        string[] to_add;
        foreach(name; addons) {
            if (assembly.raw.spec.hasAddon(name)) {
                warningf("Addon '%s' is already present in the assembly spec; skipping.", name);
                continue;
            }
            if (to_add.canFind(name)) {
                warningf("Addon '%s' is specified more than once; skipping duplicate.", name);
                continue;
            }
            to_add ~= name;
        }

        if (to_add.empty) {
            warningf("No new addons to add to the assembly spec.");
            return 0;
        }

        foreach(name; to_add)
            assembly.raw.addAddon(
                name: name,
                source_name: source.isNull ? null : source.get,
                from_odoo_apps: odooApps);

        assembly.raw.save();
        assembly.raw.repo.add(assembly.raw.spec_path);
        infof("Added addon(s) to assembly spec: %s", to_add.join(", "));

        if (commit || push || !pushTo.isNull)
            assembly.raw.repo.commit(
                message: commitMessage.isNull ?
                    "[ASSEMBLY] Add addon(s): %s".format(to_add.join(", ")) :
                    commitMessage.get,
                username: commitUser.isNull ? null : commitUser.get,
                useremail: commitEmail.isNull ? null : commitEmail.get);

        if (push || !pushTo.isNull)
            assembly.raw.push(branch_name: pushTo.isNull ? null : pushTo.get);
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

        // If a source with this name already exists, skip rather than fail.
        if (!name.isNull && !assembly.raw.spec.getSource(name.get).isNull) {
            warningf("Assembly already has a source named '%s'; skipping.", name.get);
            return 0;
        }

        auto before = assembly.raw.spec.sources.length;
        assembly.raw.addSource(
            git_url: GitURL(git_url),
            name: name.isNull ? null : name.get,
            git_ref: gitRef.isNull ? null : gitRef.get);
        if (assembly.raw.spec.sources.length == before) {
            warningf("Source %s is already present in the assembly spec; skipping.", git_url);
            return 0;
        }

        assembly.raw.save();
        assembly.raw.repo.add(assembly.raw.spec_path);
        infof("Added source %s to assembly spec.", git_url);

        if (commit || push || !pushTo.isNull)
            assembly.raw.repo.commit(
                message: commitMessage.isNull ?
                    "[ASSEMBLY] Add source: %s".format(git_url) : commitMessage.get,
                username: commitUser.isNull ? null : commitUser.get,
                useremail: commitEmail.isNull ? null : commitEmail.get);

        if (push || !pushTo.isNull)
            assembly.raw.push(branch_name: pushTo.isNull ? null : pushTo.get);

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
        this.add(new CommandAssemblyRelease());
        this.add(new CommandAssemblyLink());
        this.add(new CommandAssemblyPull());
        this.add(new CommandAssemblyUpgrade());
        this.add(new CommandAssemblyUpgradeSources());
        this.add(new CommandAssemblyAddAddon());
        this.add(new CommandAssemblyAddSource());
    }
}
