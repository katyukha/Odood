module odood.cli.program;
private import odood.lib: _version;

private import commandr: Program, ProgramArgs, Option, Flag, parse;

private import odood.cli.command: OdoodCommand;
private import odood.cli.init: CommandInit;
private import odood.cli.server:
    CommandServer, CommandServerStart, CommandServerStop, CommandServerRestart;
private import odood.cli.database: CommandDatabase;
private import odood.cli.status: CommandStatus;


class OdoodProgram: Program {

    this() {
        super("odood", _version);
        this.summary("Easily manage odoo installations.");
        this.add(new CommandInit());
        this.add(new CommandServer());
        this.add(new CommandStatus());
        this.add(new CommandDatabase());

        // shortcuts
        this.add(new CommandServerStart());
        this.add(new CommandServerStop());
        this.add(new CommandServerRestart());
    }


    void run(ref string[] args) {
        auto pargs = this.parse(args);
        if (pargs.command !is null) {
            OdoodCommand cmd = cast(OdoodCommand)this.commands[pargs.command.name];
            if (cmd) {
                cmd.execute(pargs.command);
            } else {
                // raise error
            }
        } else {
        }
    }
}

