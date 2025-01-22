/// Module provides various odoo related routings
module odood.cli.commands.odoo;

private import std.logger;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
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
            new Argument(
                "dbname", "Name of database to recompute fields for").required);
        this.add(
            new Argument(
                "model", "Name of model to recompute fields for").required);

    }

    public override void execute(ProgramArgs args) {
        Project.loadProject.lodoo.recomputeField(args.arg("dbname"), args.arg("model"), args.options("field"));
    }
}


class CommandOdoo: OdoodCommand {
    this() {
        super("odoo", "Odoo-related utility commands.");
        this.add(new CommandOdooShell());
        this.add(new CommandOdooRecomputeField());
    }
}


