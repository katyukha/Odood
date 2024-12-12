module odood.cli.commands.precommit;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import thepath: Path;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;
private import odood.lib.devtools.precommit:
    initPreCommit,
    setUpPreCommit;


class CommandPreCommitInit: OdoodCommand {
    this() {
        super("init", "Initialize pre-commit for this repo.");
        this.add(new Flag(
            "f", "force",
            "Enforce initialization. " ~
            "This will rewrite pre-commit configurations.")),
        this.add(new Flag(
            null, "no-setup",
            "Do not set up pre-commit. " ~
            "Could be used if pre-commit already set up.")),
        this.add(new Argument(
            "path", "Path to repository to initialize pre-commit.").optional());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            args.arg("path") ? Path(args.arg("path")) : Path.current);

        repo.initPreCommit(args.flag("force"), !args.flag("no-setup"));
    }

}

class CommandPreCommitSetUp: OdoodCommand {
    this() {
        super("set-up", "Set up pre-commit for specified repo.");
        this.add(new Argument(
            "path", "Path to repository to configure.").optional());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto repo = project.addons.getRepo(
            args.arg("path") ? Path(args.arg("path")) : Path.current);

        repo.setUpPreCommit();
    }

}


class CommandPreCommitRun: OdoodCommand {
    this() {
        super("run", "Run pre-commit for specified repo.");
        this.add(new Argument(
            "path", "Path to repository to run pre-commit for.").optional());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        auto path = args.arg("path") ? Path(args.arg("path")) : Path.current;
        project.venv.runner
            .withArgs("pre-commit", "run", "--all-files")
            .inWorkDir(path)
            .execv();
    }

}


class CommandPreCommit: OdoodCommand {
    this() {
        super("pre-commit", "Work with pre-commit dev tool.");
        this.add(new CommandPreCommitInit());
        this.add(new CommandPreCommitSetUp());
        this.add(new CommandPreCommitRun());
    }
}
