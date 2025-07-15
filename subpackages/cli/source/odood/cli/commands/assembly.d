module odood.cli.commands.assembly;

private import std.json;
private import std.exception: enforce;
private import std.stdio: writefln, writeln;
private import std.array: empty;
private import std.format: format;

private import colored;
private import commandr: Argument, Option, Flag, ProgramArgs;
private import thepath: Path;

private import odood.lib.assembly: Assembly;
private import odood.lib.project: Project;
private import odood.utils.addons.addon: OdooAddon;
private import odood.git: parseGitURL;
private import odood.cli.core: OdoodCommand, OdoodCLIException;
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

class CommandAssemblySync: OdoodCommand {
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
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        enforce!OdoodCLIException(
            !project.assembly.isNull,
            "Assembly not initialized!");
        project.assembly.get.sync(
            commit: args.flag("commit"),
            commit_message: args.option("commit-message"),
            commit_username: args.option("commit-user"),
            commit_useremail: args.option("commit-user"),
        );
    }
}

class CommandAssemblyLink: OdoodCommand {
    this() {
        super("link", "Link addons from this assembly to custom addons");
        this.add(new Flag(
            null, "manifest-requirements",
            "Install python dependencies from manifest's external dependencies"));
        this.add(new Flag(
            null, "ual", "Update addons list for all databases"));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        enforce!OdoodCLIException(
            !project.assembly.isNull,
            "Assembly not initialized!");
        project.assembly.get.link(
            manifest_requirements: args.flag("manifest-requirements"),
        );
        if (args.flag("ual"))
            foreach(dbname; project.databases.list())
                project.lodoo.addonsUpdateList(dbname);
    }
}


class CommandAssemblyPull: OdoodCommand {
    this() {
        super("pull", "Pull updates for this assembly.");
        this.add(new Flag(
            null, "link",
            "Relink addons in this assembly after pull"));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        enforce!OdoodCLIException(
            !project.assembly.isNull,
            "Assembly not initialized!");
        auto assembly = project.assembly.get;

        assembly.pull;

        if (args.flag("link") || args.flag("update-addons"))
            assembly.link();
    }
}


class CommandAssemblyUpgrade: OdoodCommand {
    this() {
        super("upgrade", "Upgrade assembly (optionally do backup, pull changes, update addons).");
        this.add(new Flag(
            null, "backup",
            "Do backup of all databases"));
        this.add(new Flag(
            null, "skip-errors", "Continue upgrade next databases if upgrade of db had error."));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        enforce!OdoodCLIException(
            !project.assembly.isNull,
            "Assembly not initialized!");
        auto assembly = project.assembly.get;

        if (args.flag("backup"))
            foreach(db; project.databases.list)
                project.databases.backup(db);

        assembly.pull;
        assembly.link();

        auto start_again=false;
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
        this.add(new CommandAssemblyInit());
        this.add(new CommandAssemblyUse());
        this.add(new CommandAssemblyStatus());
        this.add(new CommandAssemblySync());
        this.add(new CommandAssemblyLink());
        this.add(new CommandAssemblyPull());
        this.add(new CommandAssemblyUpgrade());
    }
}


