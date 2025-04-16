module odood.cli.commands.repository;

private import std.logger: infof, warningf;
private import std.format: format;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import thepath: Path;
private import versioned: VersionPart;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.devtools.utils: fixVersionConflict, updateManifestSerie, updateManifestVersion;
private import odood.utils.addons.addon_manifest: tryParseOdooManifest;
private import odood.git: GIT_REF_WORKTREE;


class CommandRepositoryAdd: OdoodCommand {
    this() {
        super("add", "Add git repository to Odood project.");
        this.add(new Flag(
            null, "oca",
            "Add Odoo Community Association (OCA) repository. " ~
            "If set, then 'repo' argument could be specified as " ~
            "name of repo under 'https://github.com/OCA' organuzation.")),
        this.add(new Flag(
            null, "github",
            "Add github repository. " ~
            "If set, then 'repo' argument could be specified as " ~
            "'owner/name' that will be converted to " ~
            "'https://github.com/owner/name'.")),
        this.add(new Flag(
            null, "single-branch",
            "Clone repository wihth --single-branch options. " ~
            "This could significantly reduce size of data to be downloaded " ~
            "and increase performance."));
        this.add(new Flag(
            "r", "recursive",
            "If set, then system will automatically fetch recursively " ~
            "dependencies of this repository, specified in " ~
            "odoo_requirements.txt file inside clonned repo."));
        this.add(new Option(
            "b", "branch", "Branch to clone"));
        this.add(new Flag(
            null, "ual", "Update addons list."));
        this.add(new Argument("repo", "Repository URL to clone from.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        string git_url = args.arg("repo");
        if (args.flag("oca"))
            // TODO: Add validation
            git_url = "https://github.com/OCA/%s".format(git_url);
        else if (args.flag("github"))
            // TODO: Add validation
            git_url = "https://github.com/%s".format(git_url);

        project.addons.addRepo(
            git_url,
            args.option("branch") ?
                args.option("branch") : project.odoo.branch,
            args.flag("single-branch"),
            args.flag("recursive"));

        if (args.flag("ual"))
            foreach(dbname; project.databases.list())
                project.lodoo.addonsUpdateList(dbname);
    }
}


// TODO: Move to devtools section
class CommandRepositoryFixVersionConflict: OdoodCommand {
    this() {
        super(
            "fix-version-conflict",
            "Fix version conflicts in manifests of addons in this repo.");
        this.add(new Argument(
            "path", "Path to repository to fix conflicts in.").optional());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            args.arg("path") ? Path(args.arg("path")) : Path.current);
        foreach(addon; repo.addons)
            addon.path.join("__manifest__.py").fixVersionConflict(
                    project.odoo.serie);
    }
}


// TODO: Move to devtools section
class CommandRepositoryFixSerie: OdoodCommand {
    this() {
        super(
            "fix-series",
            "Fix series in manifests of addons in this repo. Set series to project's serie");
        this.add(new Argument(
            "path", "Path to repository to fix conflicts in.").optional());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            args.arg("path") ? Path(args.arg("path")) : Path.current);
        foreach(addon; repo.addons)
            addon.path.join("__manifest__.py").updateManifestSerie(
                    project.odoo.serie);
    }
}


// TODO: Move to devtools section
// - Parse git status,
// - Find changed addons
// - increment versions of changed addons
class CommandRepositoryBumpAddonVersion: OdoodCommand {
    this() {
        super(
            "bump-versions",
            "Bump versions for modules that have changes (comparably to stable branch (17.0, 18.0, ...)).");
        this.add(new Argument(
            "path", "Path to repository to search for addons to bump versions.").optional());
        this.add(new Flag(
            null, "major", "Increase major version for addons."));
        this.add(new Flag(
            null, "minor", "Increase minor version for addons."));
        this.add(new Flag(
            null, "patch", "Increase patch version for addons."));
        this.add(new Flag(
            null, "ignore-translations", "Ignore translations."));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;


        auto start_ref = "origin/%s".format(project.odoo.serie);
        auto end_ref = GIT_REF_WORKTREE;

        auto version_part = VersionPart.PATCH;
        if (args.flag("major"))
            version_part = VersionPart.MAJOR;
        else if (args.flag("minor"))
            version_part = VersionPart.MINOR;
        else if (args.flag("patch"))
            version_part = VersionPart.PATCH;

        auto repo = project.addons.getRepo(
            args.arg("path") ? Path(args.arg("path")).toAbsolute : Path.current);
        foreach(addon; repo.getChangedModules(start_ref, end_ref, args.flag("ignore-translations"))) {
            infof("Checking module %s if version bump needed...", addon);
            auto g_path = addon.path.relativeTo(repo.path);
            auto g_manifest_path = g_path.join("__manifest__.py");
            auto start_manifest = tryParseOdooManifest(repo.getContent(g_manifest_path, start_ref));
            if (start_manifest.isNull) {
                // This is new addon. Thus, just skip it.
                warningf("Cannot read start manifest for %s. Skipping", addon);
                continue;
            }

            auto end_manifest = tryParseOdooManifest(repo.getContent(g_manifest_path));
            if (end_manifest.isNull) {
                // It seems that this is not addon (or it was removed). Thus, skip it.
                warningf("Cannot read current manifest for %s. It seems to be new addon. Skipping", addon);
                continue;
            }

            auto start_version = start_manifest.get.module_version;
            auto end_version = end_manifest.get.module_version;
            if (!start_version.isStandard || !end_version.isStandard) {
                // We cannot work with non-standard versions. thus skip them
                warningf("Non-standard start (%s) or current (%s) version of addon %s. Skipping", start_version, end_version, addon);
                continue;
            }

            if (start_version.serie != end_version.serie) {
                // Series differs. Thus skip. Let human deal with it.
                warningf("Start version serie (%s) != current version serie (%s) for addon %s. Skipping", start_version.serie, end_version.serie, addon);
                continue;
            }

            auto new_version = end_version;
            if (end_version < start_version) {
                // End version is smaller then start version. Fix it firest.
                infof("Current version is less then stable version. Swapping first...");
                new_version = start_version;
            }

            if (new_version == start_version || new_version.differAt(start_version) > version_part) {
                new_version = new_version.incVersion(version_part);
                infof("Updating manifest version: %s -> %s", end_version, new_version);
                addon.path.join("__manifest__.py").updateManifestVersion(new_version);
            }
        }
    }
}


class CommandRepository: OdoodCommand {
    this() {
        super("repo", "Manage git repositories.");
        this.add(new CommandRepositoryAdd());
        this.add(new CommandRepositoryFixVersionConflict());
        this.add(new CommandRepositoryFixSerie());
        this.add(new CommandRepositoryBumpAddonVersion());
    }
}


