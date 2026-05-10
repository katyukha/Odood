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
private import odood.lib.addons.repository: AddonRepository;
private import odood.utils.odoo.std_version: OdooStdVersion;
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
        auto end_ref = GIT_REF_WORKTREE;

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

        bool has_changes = false;
        foreach(addon; repo.getChangedModules(start_ref, end_ref, ignoreTranslations)) {
            has_changes = true;
            infof("Checking module %s if version bump needed...", addon);
            auto maybe_start_version = repo.getAddonVersion(addon, start_ref);
            if (maybe_start_version.isNull) {
                warningf("Cannot read start version for %s. May be it is new addon. Skipping", addon);
                continue;
            }

            auto maybe_end_version = repo.getAddonVersion(addon, GIT_REF_WORKTREE);
            if (maybe_end_version.isNull) {
                warningf("Cannot read current version for %s. It seems that this is not addon or it was removed. Skipping", addon);
                continue;
            }

            auto start_version = maybe_start_version.get;
            auto end_version = maybe_end_version.get;
            if (!start_version.isStandard || !end_version.isStandard) {
                warningf("Non-standard start (%s) or current (%s) version of addon %s. Skipping", start_version, end_version, addon);
                continue;
            }

            if (start_version.serie != end_version.serie) {
                warningf("Start version serie (%s) != current version serie (%s) for addon %s. Skipping", start_version.serie, end_version.serie, addon);
                continue;
            }

            auto new_version = end_version;
            if (end_version < start_version) {
                infof("Current version is less then stable version. Swapping first...");
                new_version = start_version;
            }

            if (new_version == start_version || new_version.differAt(start_version) > version_part) {
                new_version = new_version.incVersion(version_part);
                infof("Updating manifest version: %s -> %s", end_version, new_version);
                addon.path.join("__manifest__.py").updateManifestVersion(new_version);
            }
        }
        if (!has_changes)
            infof("There are no changes in modules");
        return 0;
    }
}


class CommandRepositoryCheckVersion: OdoodCommand {
    Nullable!Path path;
    bool ignoreTranslations;

    this() {
        super(
            "check-versions",
            "Check changed addons has updated versions.");
        this.addArgument!(path)("path",
            "Path to repository to search for addons to bump versions.")
            .acceptsDirectories();
        this.addFlag!(ignoreTranslations)("", "ignore-translations", "Ignore translations.");
    }

    override int execute() {
        auto project = Project.loadProject;

        auto start_ref = "origin/%s".format(project.odoo.serie);
        auto end_ref = GIT_REF_WORKTREE;

        auto repo = project.addons.getRepo(
            path.isNull ? Path.current : path.get.toAbsolute);

        repo.fetchOrigin(project.odoo.serie.toString);

        bool has_changes = false;
        foreach(addon; repo.getChangedModules(start_ref, end_ref, ignoreTranslations)) {
            has_changes = true;
            infof("Checking module %s if version bump needed...", addon);
            auto maybe_start_version = repo.getAddonVersion(addon, start_ref);
            if (maybe_start_version.isNull)
                continue;

            auto maybe_end_version = repo.getAddonVersion(addon, GIT_REF_WORKTREE);
            if (maybe_end_version.isNull)
                continue;

            auto start_version = maybe_start_version.get;
            auto end_version = maybe_end_version.get;
            enforce!OdoodCLIException(
                end_version.isStandard,
                "Non-standard current (%s) version of addon %s. Please, use standard versions for addons in format %s.X.Y.Z".format(end_version, addon.name, project.odoo.serie.toString));
            if (!start_version.isStandard)
                continue;

            enforce!OdoodCLIException(
                end_version.serie == project.odoo.serie,
                "Addon (%s) serie (%s) does not match project serie (%s)!".format(
                    addon.name, end_version.serie, project.odoo.serie));

            enforce!OdoodCLIException(
                start_version < end_version,
                "Addon (%s) current version (%s) must be greater then addon stable version (%s).".format(
                    addon.name, start_version, end_version));
        }
        if (!has_changes)
            infof("There are no changes in modules");
        return 0;
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
    }
}
