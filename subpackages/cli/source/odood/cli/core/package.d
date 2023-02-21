module odood.cli.core;

public import odood.cli.core.command;
public import odood.cli.core.program;
public import odood.cli.core.exception;


/** Exit from app with specific error code
  *
  * Params:
  *     exit_code = number represeting exit code to terminate program with.
  *     msg = optional message. Currently, it is not used, and may be specified
  *         to improve readability of code. Possibly, in future, it could be
  *         pritent to error stream.
  * Throws:
  *     OdoodCLIExitException - exception used to specify exit code for the
  *         program.
  **/
void exitWithCode(in int exit_code, in string msg=null) {
    throw new OdoodCLIExitException(exit_code, msg);
}
