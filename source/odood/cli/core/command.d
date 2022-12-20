module odood.cli.core.command;

private import std.exception: enforce;
private import std.format: format;
private import commandr: Command, ProgramArgs;
private import odood.cli.core.exception:
    OdoodCLICommandNoExecuteException;


class OdoodCommand: Command {

    this(Args...)(auto ref Args args) { super(args); }

    public void execute(ProgramArgs args) {
        auto cmd = this.commands[args.command.name];
        OdoodCommand ocmd = cast(OdoodCommand) cmd;
        enforce!OdoodCLICommandNoExecuteException(
            ocmd,
            "Command %s must be inherited from OdoodCommand and " ~
            "implement 'execute' method!".format(args.command.name));

        ocmd.execute(args.command);
    }
}
