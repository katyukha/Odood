module odood.cli.app;

private import commandr: Program, ProgramArgs, Option, Flag, parse;

private import odood.lib: _version;
private import odood.cli.core: OdoodProgram, OdoodCommand;
private import odood.cli.commands.init: CommandInit;
private import odood.cli.commands.server:
    CommandServer, CommandServerStart, CommandServerStop, CommandServerRestart;
private import odood.cli.commands.database: CommandDatabase, CommandDatabaseList;
private import odood.cli.commands.status: CommandStatus;


class App: OdoodProgram {

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
        this.add(new CommandDatabaseList("lsd"));
    }
}
