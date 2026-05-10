module odood.cli.core;

public import odood.cli.core.command;
public import odood.cli.core.program;
public import odood.cli.core.exception;


/** Exit from app with specific error code.
  *
  * Params:
  *     exit_code = number representing exit code to terminate program with.
  *     msg = optional message printed to stderr on non-zero exit.
  * Throws:
  *     DarkCommandExitException
  **/
void exitWithCode(in int exit_code, in string msg=null) {
    import darkcommand : DarkCommandExitException;
    throw new DarkCommandExitException(exit_code, msg);
}
