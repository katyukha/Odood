module odood.cli.core.program;

private import std.exception: enforce;
private import std.format: format;
private import commandr: Program, ProgramArgs, parse;
private import odood.cli.core.command: OdoodCommand;
private import odood.cli.core.exception:
    OdoodCLIExitException, OdoodCLICommandNoExecuteException;


class OdoodProgram: Program {

    this(Args...)(auto ref Args args) { super(args); }

    /** Called before running the program.
      * Could be used by subclasses to make some pre-processing before
      * running command.
      **/
    protected void setup(scope ref ProgramArgs args) {};

    int run(ref string[] args) {
        auto pargs = this.parse(args);
        setup(pargs);
        if (pargs.command !is null) {

            auto cmd = this.commands[pargs.command.name];
            OdoodCommand ocmd = cast(OdoodCommand) cmd;
            enforce!OdoodCLICommandNoExecuteException(
                ocmd,
                "Command %s must be inherited from OdoodCommand and " ~
                "implement 'execute' method!".format(pargs.command.name));

            try {
                ocmd.execute(pargs.command);
            } catch (OdoodCLIExitException e) {
                return e.exit_code;
            }
        }
        // No command have to be called
        return 0;
    }
}

