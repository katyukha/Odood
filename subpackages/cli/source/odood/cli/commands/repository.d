module odood.cli.commands.repository;

private import std.format: format;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import thepath: Path;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.odoo.utils: fixVersionConflict;


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


class CommandRepository: OdoodCommand {
    this() {
        super("repo", "Manage git repositories.");
        this.add(new CommandRepositoryAdd());
        this.add(new CommandRepositoryFixVersionConflict());
    }
}


