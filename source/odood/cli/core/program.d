module odood.cli.core.program;

private import commandr: Program, parse;
private import odood.cli.core.command: OdoodCommand;


class OdoodProgram: Program {

    this(Args...)(auto ref Args args) { super(args); }

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

