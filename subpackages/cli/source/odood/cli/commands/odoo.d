/// Module provides various odoo related routings
module odood.cli.commands.odoo;

private import std.logger;
private import std.exception: enforce;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.project: Project;


// TODO: May be move all this to dev-tools
class CommandOdooShell: OdoodCommand {
    this() {
        super("shell", "Odoo-related utility commands.");
        this.add(
            new Option(
                "d", "db", "Database(s) to run shell for."
            ));
    }

    public override void execute(ProgramArgs args) {
        auto runner = Project.loadProject.server.getServerRunner("shell");
        if (args.option("db"))
            runner.addArgs("-d", args.option("db"));
        runner.execv;
    }
}


class CommandOdooRecomputeField: OdoodCommand {
    this() {
        super("recompute", "Odoo-related utility commands.");
        this.add(
            new Option(
                "f", "field", "Name of field to recompute."
            ).repeating);
        this.add(
            new Option(
                "d", "db", "Name of database to recompute fields for."
            ).repeating);
        this.add(
            new Flag(
                null, "all-db", "Recompute for all databases."
            ));
        this.add(
            new Option(
                "m", "model", "Name of model to recompute fields for").required);

    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        string[] db_names = args.flag("all-db") ? project.databases.list() : args.options("db");
        enforce!OdoodCLIException(
            db_names.length > 0,
            "At least one database must be specified to recompute field");

        foreach(dbname; db_names) {
            infof("Recomputing fields: db=%s, model=%s, fields=%s", dbname, args.option("model"), args.options("field"));
            project.lodoo.recomputeField(dbname, args.option("model"), args.options("field"));
        }
    }
}


class CommandOdoo: OdoodCommand {
    this() {
        super("odoo", "Odoo-related utility commands.");
        this.add(new CommandOdooShell());
        this.add(new CommandOdooRecomputeField());
    }
}


