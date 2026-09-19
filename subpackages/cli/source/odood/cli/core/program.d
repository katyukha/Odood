module odood.cli.core.program;

private import std.typecons: Nullable;

private import darkcommand: Program, addOption;


/** Base class for the Odood CLI program.
  *
  * Carries the global `--config` option, which lets any invocation address a
  * specific Odood project instead of discovering one from the current working
  * directory. Commands consume it through `OdoodCommand.loadProject`.
  **/
class OdoodProgram: Program {

    /** Value of the global `--config` option: path to an `odood.yml` file or
      * to a directory containing one. Null when the option was not provided,
      * in which case the project is discovered from the current directory.
      **/
    Nullable!string config_path;

    this(Args...)(auto ref Args args) {
        super(args);
        this.addOption!(config_path)(
            "c", "config",
            "Path to odood.yml or to a directory containing it. " ~
            "When not set, the project is discovered from the current " ~
            "directory upwards. Must be specified before the command name.")
            .completesAsPath();
    }
}
