module odood.cli.command;

private import commandr: Command, Program, ProgramArgs, parse;



class OdoodCommand: Command {

    this(Args...)(auto ref Args args) { super(args); }

    public void execute(ProgramArgs args) {
        /// By default run sub command
        OdoodCommand cmd = cast(OdoodCommand)this.commands[args.command.name];

        if (cmd) {
            cmd.execute(args.command);
        } else {
            // raise error
        }
    }
}
