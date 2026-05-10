module odood.cli.commands.precommit;

private import std.typecons: Nullable;

private import thepath: Path;
private import darkcommand;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.devtools.precommit:
    initPreCommit,
    initPreCommitOdooHelper,
    setUpPreCommit,
    updatePreCommit;


class CommandPreCommitInit: OdoodCommand {
    bool force;
    bool noSetup;
    bool odooHelperCompat;
    Nullable!string path;

    this() {
        super("init", "Initialize pre-commit for this repo.");
        this.addFlag!(force)("f", "force",
            "Enforce initialization. This will rewrite pre-commit configurations.");
        this.addFlag!(noSetup)("", "no-setup",
            "Do not set up pre-commit. Could be used if pre-commit already set up.");
        this.addFlag!(odooHelperCompat)("", "odoo-helper-compat",
            "Generate pre-commit config compatible with odoo-helper linting style " ~
            "(check-only, no auto-formatting).");
        this.addArgument!(path)("path",
            "Path to repository to initialize pre-commit.")
            .acceptsDirectories();
    }

    override int execute() {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            !path.isNull ? Path(path.get) : Path.current);

        if (odooHelperCompat)
            project.initPreCommitOdooHelper(repo, force, !noSetup);
        else
            project.initPreCommit(repo, force, !noSetup);
        return 0;
    }
}


class CommandPreCommitSetUp: OdoodCommand {
    Nullable!string path;

    this() {
        super("set-up", "Set up pre-commit for specified repo.");
        this.addArgument!(path)("path", "Path to repository to configure.")
            .acceptsDirectories();
    }

    override int execute() {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            !path.isNull ? Path(path.get) : Path.current);

        project.setUpPreCommit(repo);
        return 0;
    }
}


class CommandPreCommitUpdate: OdoodCommand {
    Nullable!string path;

    this() {
        super("update", "Update pre-commit for specified repo.");
        this.addArgument!(path)("path", "Path to repository to configure.")
            .acceptsDirectories();
    }

    override int execute() {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            !path.isNull ? Path(path.get) : Path.current);

        project.updatePreCommit(repo);
        return 0;
    }
}


class CommandPreCommitRun: OdoodCommand {
    Nullable!string path;

    this() {
        super("run", "Run pre-commit for specified repo.");
        this.addArgument!(path)("path", "Path to repository to run pre-commit for.")
            .acceptsDirectories();
    }

    override int execute() {
        auto project = Project.loadProject;
        auto repo_path = !path.isNull ? Path(path.get) : Path.current;
        project.venv.runner
            .withArgs("pre-commit", "run", "--all-files")
            .inWorkDir(repo_path)
            .execv();
        return 0;
    }
}


class CommandPreCommit: OdoodCommand {
    this() {
        super("pre-commit", "Work with pre-commit dev tool.");
        this.add(new CommandPreCommitInit());
        this.add(new CommandPreCommitSetUp());
        this.add(new CommandPreCommitUpdate());
        this.add(new CommandPreCommitRun());
    }
}
