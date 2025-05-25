module odood.cli.commands.assembly;

private import std.json;
private import std.exception: enforce;
private import std.stdio: writefln, writeln;
private import std.array: empty;

private import colored;
private import commandr: Option, Flag, ProgramArgs;

private import odood.lib.assembly: Assembly;
private import odood.lib.project: Project;
private import odood.git: parseGitURL;
private import odood.cli.core: OdoodCommand, OdoodCLIException;


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
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        enforce!OdoodCLIException(
            !project.assembly.isNull,
            "Assembly not initialized!");
        project.assembly.get.sync;
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


class CommandAssembly: OdoodCommand {
    this() {
        super("assembly", "Manage assembly of this project");
        this.add(new CommandAssemblyInit());
        this.add(new CommandAssemblyStatus());
        this.add(new CommandAssemblySync());
        this.add(new CommandAssemblyLink());
        this.add(new CommandAssemblyPull());
    }
}


