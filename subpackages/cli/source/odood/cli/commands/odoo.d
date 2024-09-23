/// Module provides various odoo related routings
module odood.cli.commands.odoo;

private import std.logger;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;


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


class CommandOdooRun: OdoodCommand {
    this() {
        super("run", "Run Odoo. All arguments after '--' will be passed to Odoo.");
    }

    public override void execute(ProgramArgs args) {
        // TODO: May be merge with server/run?
        //       Also, add ability to update config before running
        //       Odoo based on environment variables, that will be useful in case,
        //       when running in docker.
        Project.loadProject.server.getServerRunner()
            .addArgs(args.argsRest)
            .execv;
    }
}



class CommandOdoo: OdoodCommand {
    this() {
        super("odoo", "Odoo-related utility commands.");
        this.add(new CommandOdooShell());
        this.add(new CommandOdooRun());
    }
}


