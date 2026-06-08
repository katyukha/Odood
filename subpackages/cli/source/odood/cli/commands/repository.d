module odood.cli.commands.repository;

private import std.logger: infof, warningf, tracef, errorf;
private import std.format: format;
private import std.typecons: Nullable, nullable;
private import std.exception: enforce;

private import darkcommand;
private import thepath: Path;
private import versioned: VersionPart;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.project: Project;
private import odood.lib.devtools.utils: fixVersionConflict, updateManifestSerie, updateManifestVersion;
private import odood.utils.addons.addon_manifest: tryParseOdooManifest;
private import odood.utils.addons.addon: OdooAddon;
private import odood.lib.addons.repository: AddonRepository, PrepareReleaseResult;
private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.git: GIT_REF_WORKTREE, isGitRepo;


class CommandRepositoryAdd: OdoodCommand {
    bool oca;
    bool github;
    bool singleBranch;
    bool recursive;
    Nullable!string branch;
    bool ual;
    string repo;

    this() {
        super("add", "Add git repository to Odood project.");
        this.addFlag!(oca)("", "oca",
            "Add Odoo Community Association (OCA) repository. " ~
            "If set, then 'repo' argument could be specified as " ~
            "name of repo under 'https://github.com/OCA' organization.");
        this.addFlag!(github)("", "github",
            "Add github repository. " ~
            "If set, then 'repo' argument could be specified as " ~
            "'owner/name' that will be converted to " ~
            "'https://github.com/owner/name'.");
        this.addFlag!(singleBranch)("", "single-branch",
            "Clone repository with --single-branch options. " ~
            "This could significantly reduce size of data to be downloaded " ~
            "and increase performance.");
        this.addFlag!(recursive)("r", "recursive",
            "If set, then system will automatically fetch recursively " ~
            "dependencies of this repository, specified in " ~
            "odoo_requirements.txt file inside cloned repo.");
        this.addOption!(branch)("b", "branch", "Branch to clone");
        this.addFlag!(ual)("", "ual", "Update addons list.");
        this.addArgument!(repo)("repo", "Repository URL to clone from.");
    }

    override int execute() {
        auto project = Project.loadProject;

        string git_url = repo;
        if (oca)
            git_url = "https://github.com/OCA/%s".format(git_url);
        else if (github)
            git_url = "https://github.com/%s".format(git_url);

        project.addons.addRepo(
            git_url,
            branch.isNull ? project.odoo.branch : branch.get,
            singleBranch,
            recursive);

        if (ual)
            foreach(dbname; project.databases.list())
                project.lodoo.addonsUpdateList(dbname);
        return 0;
    }
}


class CommandRepositoryFixVersionConflict: OdoodCommand {
    Nullable!Path path;

    this() {
        super(
            "fix-version-conflict",
            "Fix version conflicts in manifests of addons in this repo.");
        this.addArgument!(path)("path", "Path to repository to fix conflicts in.")
            .acceptsDirectories();
    }

    override int execute() {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            path.isNull ? Path.current : path.get);
        foreach(addon; repo.addons)
            addon.path.join("__manifest__.py").fixVersionConflict(
                    project.odoo.serie);
        return 0;
    }
}


class CommandRepositoryFixSerie: OdoodCommand {
    Nullable!Path path;

    this() {
        super(
            "fix-series",
            "Fix series in manifests of addons in this repo. Set series to project's serie");
        this.addArgument!(path)("path", "Path to repository to fix conflicts in.")
            .acceptsDirectories();
    }

    override int execute() {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            path.isNull ? Path.current : path.get);
        foreach(addon; repo.addons)
            addon.path.join("__manifest__.py").updateManifestSerie(
                    project.odoo.serie);
        return 0;
    }
}


class CommandRepositoryBumpAddonVersion: OdoodCommand {
    Nullable!Path path;
    bool major;
    bool minor;
    bool patch;
    bool ignoreTranslations;

    this() {
        super(
            "bump-versions",
            "Bump versions for modules that have changes (comparably to stable branch).");
        this.addArgument!(path)("path",
            "Path to repository to search for addons to bump versions.")
            .acceptsDirectories();
        this.addFlag!(major)("", "major", "Increase major version for addons.");
        this.addFlag!(minor)("", "minor", "Increase minor version for addons.");
        this.addFlag!(patch)("", "patch", "Increase patch version for addons.");
        this.addFlag!(ignoreTranslations)("", "ignore-translations", "Ignore translations.");
    }

    override int execute() {
        auto project = Project.loadProject;

        auto start_ref = "origin/%s".format(project.odoo.serie);

        auto version_part = VersionPart.PATCH;
        if (major)
            version_part = VersionPart.MAJOR;
        else if (minor)
            version_part = VersionPart.MINOR;
        else if (patch)
            version_part = VersionPart.PATCH;

        auto repo = project.addons.getRepo(
            path.isNull ? Path.current : path.get.toAbsolute);

        repo.fetchOrigin(project.odoo.serie.toString);

        auto changes = repo.collectChanges(start_ref, ignore_translations: ignoreTranslations);

        if (!changes.has_changes) {
            infof("There are no changes in modules");
            return 0;
        }

        foreach(addon; changes.addons_updated) {
            infof("Checking module %s if version bump needed...", addon.name);

            auto start_version = addon.old_version;
            auto end_version = addon.new_version;

            if (!start_version.isStandard || !end_version.isStandard) {
                warningf("Non-standard start (%s) or current (%s) version of addon %s. Skipping",
                    start_version, end_version, addon.name);
                continue;
            }

            if (start_version.serie != end_version.serie) {
                warningf("Start version serie (%s) != current version serie (%s) for addon %s. Skipping",
                    start_version.serie, end_version.serie, addon.name);
                continue;
            }

            auto new_version = end_version;
            if (end_version < start_version) {
                infof("Current version is less than stable version. Swapping first...");
                new_version = start_version;
            }

            if (new_version == start_version || new_version.differAt(start_version) > version_part) {
                new_version = new_version.incVersion(version_part);
                infof("Updating manifest version: %s -> %s", end_version, new_version);
                repo.path.join(addon.new_path).join("__manifest__.py")
                    .updateManifestVersion(new_version);
            }
        }
        return 0;
    }
}


/** Run a version check of `repo` against `start_ref` and report results.
  *
  * Shared by `repo check-versions` and `repo hotfix check`. Returns 0 when all
  * changed addons have bumped versions; throws on the first violation.
  **/
private int runVersionCheck(
        AddonRepository repo,
        in OdooSerie serie,
        in string start_ref,
        in bool ignore_translations) {
    auto result = repo.checkVersions(
        expected_serie: serie,
        start_ref: start_ref,
        ignore_translations: ignore_translations);

    if (!result.has_changes) {
        infof("There are no changes in modules");
        return 0;
    }

    foreach(addon_err; result.errors)
        foreach(msg; addon_err.messages)
            enforce!OdoodCLIException(
                false,
                "Addon %s: %s".format(addon_err.addon_name, msg));

    return 0;
}


class CommandRepositoryCheckVersion: OdoodCommand {
    Nullable!Path path;
    bool ignoreTranslations;
    bool sinceLastRelease;

    this() {
        super(
            "check-versions",
            "Check changed addons has updated versions.");
        this.addArgument!(path)("path",
            "Path to repository to search for addons to bump versions.")
            .acceptsDirectories();
        this.addFlag!(ignoreTranslations)("", "ignore-translations", "Ignore translations.");
        this.addFlag!(sinceLastRelease)("", "since-last-release",
            "Compare against the latest release tag instead of the stable branch tip. "
            ~ "Shows exactly what 'odood repo release' will verify.");
    }

    override int execute() {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            path.isNull ? Path.current : path.get.toAbsolute);

        repo.fetchOrigin(project.odoo.serie.toString);

        string start_ref;
        if (sinceLastRelease) {
            auto latest = repo.getLatestRelease(project.odoo.serie);
            if (latest.isNull) {
                infof("No release tags found; comparing against origin/%s.",
                    project.odoo.serie);
                start_ref = "origin/%s".format(project.odoo.serie);
            } else {
                infof("Comparing against latest release tag: %s", latest.get);
                start_ref = latest.get.toString;
            }
        } else {
            start_ref = "origin/%s".format(project.odoo.serie);
        }

        return runVersionCheck(
            repo, project.odoo.serie, start_ref, ignoreTranslations);
    }
}


class CommandRepositoryMigrateAddons: OdoodCommand {
    Nullable!Path path;
    string[] module_;
    bool commit;

    this() {
        super(
            "migrate-addons",
            "Migrate code of addons that has older odoo serie to serie of this project.");
        this.addArgument!(path)("path", "Path to repository to migrate addons in.")
            .acceptsDirectories();
        this.addOption!(module_)("m", "module", "Name of module to migrate");
        this.addFlag!(commit)("", "commit", "Commit changes.");
    }

    override int execute() {
        import odood.lib.devtools.migrate: migrateAddonsCode;
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            path.isNull ? Path.current : path.get.toAbsolute);

        project.migrateAddonsCode(
            repo: repo,
            addon_names: module_,
            commit: commit);
        return 0;
    }
}


class CommandRepositoryDoForwardPort: OdoodCommand {
    Nullable!Path path;
    string source;

    this() {
        super(
            "do-forward-port",
            "[Experimental] Do forwardport changes from older branch.");
        this.addArgument!(path)("path", "Path to repository to migrate addons in.");
        this.addOption!(source)("s", "source",
            "Source branch to forwardport changes from");
    }

    override int execute() {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            path.isNull ? Path.current : path.get.toAbsolute);

        repo.fetchOrigin(source);

        if (!repo.gitCmd
                .withArgs("merge", "--no-ff", "--no-commit", "--edit", "origin/%s".format(source))
                .execute.isOk)
            warningf("Merge failed, there are conflicts. Please, resolve them manually");

        repo.gitCmd
            .withArgs("reset", "-q", "--", "*.po", "*.pot")
            .execute
            .ensureOk(true);

        repo.gitCmd
            .withArgs("clean", "-fdx", " --", "*.po", "*.pot")
            .execute
            .ensureOk(true);
        repo.gitCmd
            .withArgs("checkout", "--ours", "--", "*.po", "*.pot")
            .execute;
        repo.gitCmd
            .withArgs("add", "*.po", "*.pot")
            .execute;

        foreach(addon; repo.addons) {
            addon.path.join("__manifest__.py").fixVersionConflict(project.odoo.serie);

            if (!addon.path.join("migrations").exists)
                continue;

            foreach(migration_path; addon.path.join("migrations").walk) {
                auto migration_version = OdooStdVersion(migration_path.baseName);
                if (!migration_version.isStandard) {
                    warningf(
                        "Cannot migrate migration script that is not in standard format. Skipping migration of %s:%s migration...",
                        addon.name, migration_version.rawVersion);
                    continue;
                }
                if (migration_version.serie != project.odoo.serie) {
                    auto new_migration_version = migration_version.withSerie(project.odoo.serie);
                    infof("Migrating migration scripts %s:%s -> %s:%s...", addon.name, migration_version, addon.name, new_migration_version);
                    migration_path.rename(migration_path.parent.join(new_migration_version.toString));
                } else {
                    tracef("Migration of migration scripts %s:%s is not required, skipping...", addon.name, migration_version);
                }
            }
        }
        return 0;
    }
}


class CommandRepositoryPullAll: OdoodCommand {
    this() {
        super(
            "pull-all",
            "[Experimental] Pull changes from all repos and relink addons.");
    }

    private AddonRepository[] searchRepositories(in Path repo_dir) const
    in (repo_dir.isDir) {
        AddonRepository[] repositories;
        foreach(p; repo_dir.walk) {
            if (p.isGitRepo)
                repositories ~= new AddonRepository(p);
            else
                repositories ~= searchRepositories(p);
        }
        return repositories;
    }

    override int execute() {
        auto project = Project.loadProject;
        foreach(repo; searchRepositories(project.directories.repositories)) {
            auto repo_name = repo.path.relativeTo(project.directories.repositories).toString;
            if (repo.status.isClean) {
                infof("Repo %s: pulling changes...", repo_name);
                bool need_link = false;
                try {
                    string commit_start = repo.getCurrCommit;
                    repo.pull(ff_only: true);
                    string commit_end = repo.getCurrCommit;
                    if (commit_start != commit_end) {
                        need_link = true;
                        infof("Repo %s: pull completed (%s..%s)!", repo_name, commit_start, commit_end);
                    } else {
                        infof("Repo %s: Nothing to pull!", repo_name);
                    }
                } catch (Exception e) {
                    errorf("Repo %s: cannot pull repo, because following error\n%s\n---\nskipping...", repo_name, e.msg);
                    continue;
                }

                if (need_link) {
                    try {
                        infof("Repo %s: Linking...", repo_name);
                        project.addons.link(repo.path, recursive: true);
                        infof("Repo %s: Link completed...", repo_name);
                    } catch (Exception e){
                        errorf("Repo %s: cannot link repo, because following error\n%s\n---\nskipping...", repo_name, e.msg);
                    }
                }
            } else {
                warningf("Repo %s: not clean, skipping...", repo_name);
            }
        }
        return 0;
    }
}


class CommandRepositoryRelease: OdoodCommand {
    Nullable!Path path;
    bool initial;
    bool major;
    bool minor;
    bool patch;
    bool ignoreTranslations;
    bool failNothingToRelease;
    bool push;
    bool changelog;
    Nullable!string commitMessage;
    Nullable!string commitUser;
    Nullable!string commitEmail;

    this() {
        super(
            "release",
            "Release addon repository: auto-version, tag, and optionally push.");
        this.addArgument!(path)("path",
            "Path to repository to release (default: current directory).")
            .acceptsDirectories();
        this.addFlag!(initial)("", "initial",
            "Create the first release for a repository with no prior tags "
            ~ "at version <serie>.1.0.0. Skips change detection and version checking.");
        this.addFlag!(major)("", "major", "Force a major version bump.");
        this.addFlag!(minor)("", "minor", "Force a minor version bump.");
        this.addFlag!(patch)("", "patch", "Force a patch version bump.");
        this.addFlag!(ignoreTranslations)("", "ignore-translations",
            "Ignore translation files (.po/.pot) when detecting changes.");
        this.addFlag!(failNothingToRelease)("", "fail-nothing-to-release",
            "Exit with code 1 when no changed addons are detected.");
        this.addFlag!(push)("", "push", "Push the release tag (and branch) to origin.");
        this.addFlag!(changelog)("", "changelog",
            "Generate CHANGELOG.md and CHANGELOG.latest.md and commit them before tagging.");
        this.addOption!(commitMessage)("", "commit-message",
            "Commit message for the changelog commit (default: 'Release <version>').");
        this.addOption!(commitUser)("", "commit-user",
            "Git author name for the changelog commit.");
        this.addOption!(commitEmail)("", "commit-email",
            "Git author email for the changelog commit.");
    }

    override int execute() {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            path.isNull ? Path.current : path.get.toAbsolute);

        immutable serie_str = project.odoo.serie.toString;
        auto current_branch = repo.getCurrBranch();
        immutable on_stable = !current_branch.isNull && current_branch.get == serie_str;

        // A patch release (Z bump) requires the explicit --patch flag, so it is
        // always a conscious choice and is allowed from any branch. It is the
        // mainline patch — a small fix on top of the latest serie release.
        // Patching an *older* release while stable has moved on is the hotfix
        // flow instead ('odood repo hotfix'). Other release levels keep the
        // safety guards below.
        if (!patch) {
            if (push)
                enforce!OdoodCLIException(
                    on_stable,
                    ("Releases with --push must be made from branch '%s'. "
                    ~ "Current: %s. Run 'git checkout %s' first.").format(
                        serie_str,
                        current_branch.isNull ? "detached HEAD" : current_branch.get,
                        serie_str));
            else if (!on_stable)
                warningf(
                    "Releasing from branch '%s', not the stable branch '%s'.",
                    current_branch.isNull ? "detached HEAD" : current_branch.get,
                    serie_str);
        }

        if (initial) {
            enforce!OdoodCLIException(
                !major && !minor && !patch,
                "--major/--minor/--patch are not valid with --initial.");
            enforce!OdoodCLIException(
                !changelog,
                "--changelog is not valid with --initial (no changes to report).");

            auto new_version = repo.initialRelease(project.odoo.serie);
            repo.setTag(new_version.toString);
            infof("Created tag: %s", new_version);

            if (push) {
                repo.pushTag(new_version.toString);
                infof("Pushed tag to origin.");
            }
            return 0;
        }

        repo.fetchOrigin(serie_str);

        Nullable!VersionPart override_part;
        if (major)
            override_part = VersionPart.MAJOR.nullable;
        else if (minor)
            override_part = VersionPart.MINOR.nullable;
        else if (patch)
            override_part = VersionPart.PATCH.nullable;

        auto result = repo.prepareRelease(
            serie: project.odoo.serie,
            override_part: override_part,
            ignore_translations: ignoreTranslations);

        if (result.isNull) {
            infof("Nothing to release: no changed addons detected.");
            if (failNothingToRelease)
                exitWith(1);
            return 0;
        }

        if (changelog) {
            repo.generateChangelog(result.get);
            auto msg = commitMessage.isNull
                ? "Release %s".format(result.get.new_version)
                : commitMessage.get;
            repo.commit(
                msg,
                commitUser.isNull ? null : commitUser.get,
                commitEmail.isNull ? null : commitEmail.get);
            infof("Changelog committed.");
        }

        repo.setTag(result.get.new_version.toString);
        infof("Created tag: %s", result.get.new_version);

        if (push) {
            repo.push();
            repo.pushTag(result.get.new_version.toString);
            infof("Pushed branch and tag to origin.");
        }
        return 0;
    }
}


/** Parse a 'hotfix/A.B.X.Y.x' branch name into the chain's primary version.
  *
  * Returns the primary release of the chain (`A.B.X.Y.0`), or null when the
  * branch is not a hotfix branch for `serie`.
  **/
private Nullable!OdooStdVersion parseHotfixChain(in string branch, in OdooSerie serie) {
    import std.string: startsWith, endsWith;
    enum prefix = "hotfix/";
    enum suffix = ".x";
    if (!branch.startsWith(prefix) || !branch.endsWith(suffix))
        return Nullable!OdooStdVersion.init;

    // middle = "A.B.X.Y"; appending ".0" yields the primary version string.
    auto middle = branch[prefix.length .. $ - suffix.length];
    auto primary = OdooStdVersion(middle ~ ".0");
    if (!primary.isStandard || primary.serie != serie)
        return Nullable!OdooStdVersion.init;
    return primary.nullable;
}


/** Base for hotfix subcommands that operate on the current hotfix branch
  * ('check', 'release'). Provides the repo accessor and resolves the patch
  * chain base from the 'hotfix/A.B.X.Y.x' branch the command is run on.
  **/
class HotfixBranchCommand: OdoodCommand {
    Nullable!Path path;

    this(in string name, in string description) {
        super(name, description);
        this.addArgument!(path)("path",
            "Path to repository (default: current directory).")
            .acceptsDirectories();
    }

    protected AddonRepository getRepo(Project project) {
        return project.addons.getRepo(
            path.isNull ? Path.current : path.get.toAbsolute);
    }

    /** Ensure we are on a hotfix branch and return the latest tag in its chain.
      *
      * Fetches origin first so remote chain tags are visible. Throws if the
      * current branch is not a hotfix branch, or the chain has no tags.
      **/
    protected OdooStdVersion resolveChainBase(Project project, AddonRepository repo) {
        auto branch = repo.getCurrBranch();
        enforce!OdoodCLIException(
            !branch.isNull,
            "Not on a hotfix branch (detached HEAD). "
            ~ "Run 'odood repo hotfix start --from=<version>' first.");

        auto chain = parseHotfixChain(branch.get, project.odoo.serie);
        enforce!OdoodCLIException(
            !chain.isNull,
            ("Current branch '%s' is not a hotfix branch. Expected "
            ~ "'hotfix/%s.X.Y.x' — create it with "
            ~ "'odood repo hotfix start --from=<version>'.").format(
                branch.get, project.odoo.serie));

        repo.fetchOrigin(project.odoo.serie.toString);

        auto base = repo.getLatestPatch(chain.get);
        enforce!OdoodCLIException(
            !base.isNull,
            ("No tags found in the %s.%d.%d.* chain locally or on remote.").format(
                chain.get.serie, chain.get.major, chain.get.minor));
        return base.get;
    }
}


class CommandRepositoryHotfixStart: OdoodCommand {
    Nullable!Path path;
    string fromVersion;

    this() {
        super(
            "start",
            "Set up a hotfix branch from a primary release tag. "
            ~ "Run this before 'odood repo hotfix release'.");
        this.addArgument!(path)("path",
            "Path to repository (default: current directory).")
            .acceptsDirectories();
        this.addOption!(fromVersion)("", "from",
            "Primary release tag to patch (e.g. 18.0.2.1.0). Must have Z == 0.");
    }

    override int execute() {
        import std.stdio: writeln, writefln;

        auto project = Project.loadProject;
        auto repo = project.addons.getRepo(
            path.isNull ? Path.current : path.get.toAbsolute);

        enforce!OdoodCLIException(
            fromVersion.length > 0,
            "--from is required (e.g. --from=18.0.2.1.0).");

        auto primary = OdooStdVersion(fromVersion);
        enforce!OdoodCLIException(
            primary.isStandard,
            "--from '%s' is not a valid standard version tag.".format(fromVersion));
        enforce!OdoodCLIException(
            primary.patch == 0,
            ("--from must be a primary release tag (Z == 0), got: '%s'. "
            ~ "Always pass the primary release, not an existing hotfix.").format(fromVersion));
        enforce!OdoodCLIException(
            primary.serie == project.odoo.serie,
            "--from series (%s) does not match project series (%s).".format(
                primary.serie, project.odoo.serie));

        repo.fetchOrigin(project.odoo.serie.toString);

        // Find the latest tag in the A.B.X.Y.* chain — this is the actual
        // branch base (may be Z>0 if hotfixes already exist on this primary).
        auto base_version = repo.getLatestPatch(primary);
        enforce!OdoodCLIException(
            !base_version.isNull,
            "Primary release tag '%s' not found locally or on remote.".format(fromVersion));

        immutable branch_name = "hotfix/%s.%d.%d.x".format(
            primary.serie, primary.major, primary.minor);

        if (repo.hasLocalBranch(branch_name)) {
            infof("Branch '%s' already exists locally; switching to it.", branch_name);
            repo.switchBranchTo(branch_name);
        } else if (repo.hasRemoteUrl("origin") && repo.hasRemoteBranch(branch_name)) {
            infof("Branch '%s' exists on origin; checking out a tracking branch.",
                branch_name);
            repo.checkoutTrackingBranch(branch_name);
        } else {
            repo.createBranch(branch_name, base_version.get.toString);
            infof("Created branch '%s' from tag '%s'.", branch_name, base_version.get);
        }

        writeln();
        writeln("Next steps:");
        writefln("  1. Apply the fix and commit.");
        writefln("  2. Bump affected addon versions.");
        writefln("  3. Release the patch:");
        writefln("       odood repo hotfix release --changelog --push");
        writefln("  4. Cherry-pick the fix back to %s:", project.odoo.serie);
        writefln("       git checkout %s", project.odoo.serie);
        writefln("       git cherry-pick <fix-commit-hash>");

        return 0;
    }
}


class CommandRepositoryHotfixCheck: HotfixBranchCommand {
    bool ignoreTranslations;

    this() {
        super(
            "check",
            "Check addon versions on the current hotfix branch against the "
            ~ "latest tag in its patch chain. Previews what "
            ~ "'odood repo hotfix release' will verify.");
        this.addFlag!(ignoreTranslations)("", "ignore-translations",
            "Ignore translation files (.po/.pot) when detecting changes.");
    }

    override int execute() {
        auto project = Project.loadProject;
        auto repo = getRepo(project);
        auto base = resolveChainBase(project, repo);

        infof("Comparing against latest patch in chain: %s", base);
        return runVersionCheck(
            repo, project.odoo.serie, base.toString, ignoreTranslations);
    }
}


class CommandRepositoryHotfixRelease: HotfixBranchCommand {
    bool ignoreTranslations;
    bool failNothingToRelease;
    bool push;
    bool changelog;
    Nullable!string commitMessage;
    Nullable!string commitUser;
    Nullable!string commitEmail;

    this() {
        super(
            "release",
            "Release a hotfix (patch) on the current hotfix branch: bump Z on "
            ~ "top of the chain's latest tag, tag, and optionally push.");
        this.addFlag!(ignoreTranslations)("", "ignore-translations",
            "Ignore translation files (.po/.pot) when detecting changes.");
        this.addFlag!(failNothingToRelease)("", "fail-nothing-to-release",
            "Exit with code 1 when no changed addons are detected.");
        this.addFlag!(push)("", "push", "Push the release tag (and branch) to origin.");
        this.addFlag!(changelog)("", "changelog",
            "Generate CHANGELOG.md and CHANGELOG.latest.md and commit them before tagging.");
        this.addOption!(commitMessage)("", "commit-message",
            "Commit message for the changelog commit (default: 'Release <version>').");
        this.addOption!(commitUser)("", "commit-user",
            "Git author name for the changelog commit.");
        this.addOption!(commitEmail)("", "commit-email",
            "Git author email for the changelog commit.");
    }

    override int execute() {
        auto project = Project.loadProject;
        auto repo = getRepo(project);
        auto base = resolveChainBase(project, repo);

        infof("Releasing hotfix on chain base: %s", base);

        auto result = repo.prepareRelease(
            serie: project.odoo.serie,
            override_part: VersionPart.PATCH.nullable,
            ignore_translations: ignoreTranslations,
            base_version: base.nullable);

        if (result.isNull) {
            infof("Nothing to release: no changed addons detected.");
            if (failNothingToRelease)
                exitWith(1);
            return 0;
        }

        if (changelog) {
            repo.generateChangelog(result.get);
            auto msg = commitMessage.isNull
                ? "Release %s".format(result.get.new_version)
                : commitMessage.get;
            repo.commit(
                msg,
                commitUser.isNull ? null : commitUser.get,
                commitEmail.isNull ? null : commitEmail.get);
            infof("Changelog committed.");
        }

        repo.setTag(result.get.new_version.toString);
        infof("Created tag: %s", result.get.new_version);

        if (push) {
            repo.push();
            repo.pushTag(result.get.new_version.toString);
            infof("Pushed branch and tag to origin.");
        }
        return 0;
    }
}


class CommandRepositoryHotfix: OdoodCommand {
    this() {
        super("hotfix",
            "Manage hotfix (patch) releases on dedicated hotfix branches.");
        this.add(new CommandRepositoryHotfixStart());
        this.add(new CommandRepositoryHotfixCheck());
        this.add(new CommandRepositoryHotfixRelease());
    }
}


class CommandRepository: OdoodCommand {
    this() {
        super("repo", "Manage git repositories.");
        this.add(new CommandRepositoryAdd());
        this.add(new CommandRepositoryPullAll());
        this.add(new CommandRepositoryFixVersionConflict());
        this.add(new CommandRepositoryFixSerie());
        this.add(new CommandRepositoryBumpAddonVersion());
        this.add(new CommandRepositoryCheckVersion());
        this.add(new CommandRepositoryMigrateAddons());
        this.add(new CommandRepositoryDoForwardPort());
        this.add(new CommandRepositoryRelease());
        this.add(new CommandRepositoryHotfix());
    }
}
