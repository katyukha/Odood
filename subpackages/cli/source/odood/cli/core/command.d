module odood.cli.core.command;

private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable, nullable;

private import darkcommand: Command;
private import thepath: Path;

private import odood.project: Project;
private import odood.cli.core.exception: OdoodCLIException;
private import odood.cli.core.program: OdoodProgram;


/** Base class for all Odood CLI commands.
  *
  * Commands must load the project via `this.loadProject` (not the static
  * `Project.loadProject`, which only discovers from the current directory)
  * so the global `--config` option is honored.
  **/
class OdoodCommand: Command {

    this(Args...)(auto ref Args args) {
        super(args);
    }

    /// Path passed via the global `--config` option; null when not provided
    /// or when the command runs outside an `OdoodProgram`.
    protected Nullable!string explicitConfigPath() {
        auto prog = ancestorOrNull!OdoodProgram;
        if (prog is null)
            return Nullable!string.init;
        return prog.config_path;
    }

    /** Load the project this command operates on: from the global `--config`
      * path when provided (an unresolvable explicit path is an error, never
      * a silent fallback to discovery), otherwise via standard discovery
      * from the current directory.
      **/
    Project loadProject() {
        auto config_path = explicitConfigPath;
        if (config_path.isNull)
            return Project.loadProject;
        auto res = Project.maybeLoadProject(Path(config_path.get));
        enforce!OdoodCLIException(
            !res.isNull,
            "Cannot load Odood project from '%s' (--config): expected a path to odood.yml or to a directory containing it.".format(
                config_path.get));
        return res.get;
    }

    /** Same as `loadProject`, but returns a null result when no project is
      * discovered. An explicitly configured path must still resolve.
      **/
    Nullable!Project maybeLoadProject() {
        auto config_path = explicitConfigPath;
        if (config_path.isNull)
            return Project.maybeLoadProject;
        return loadProject().nullable;
    }
}

version(unittest) {
    private class TestConfigProgram: OdoodProgram {
        this() {
            super("test-odood", "0.0.1");
            add(new TestConfigCommand());
        }
    }

    private class TestConfigCommand: OdoodCommand {
        this() {
            super("dummy", "Test command");
        }
    }
}

// The global --config option must reach loadProject from any command, both as
// a path to odood.yml and as a directory containing it; a path that does not
// resolve to a project is an error, never a fallback to discovery.
unittest {
    import std.exception: assertThrown;
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;
    import odood.utils.odoo.serie: OdooSerie;

    auto temp_dir = createTempPath();
    scope(exit) temp_dir.remove();

    temp_dir.join("proj").mkdir(true);
    auto saved = new Project(temp_dir.join("proj"), OdooSerie("17.0"));
    saved.save();

    auto app = new TestConfigProgram();

    auto cmd = cast(TestConfigCommand) app.parseOnly(
        ["test-odood", "--config", saved.project_root.toString, "dummy"]);
    cmd.explicitConfigPath.isNull.shouldBeFalse;
    cmd.loadProject.project_root.shouldEqual(saved.project_root);
    cmd.maybeLoadProject.get.project_root.shouldEqual(saved.project_root);

    // Direct path to the config file works too.
    cmd = cast(TestConfigCommand) app.parseOnly(
        ["test-odood", "--config",
         saved.project_root.join("odood.yml").toString, "dummy"]);
    cmd.loadProject.project_root.shouldEqual(saved.project_root);

    // Explicit path without a project: hard error, no silent discovery.
    cmd = cast(TestConfigCommand) app.parseOnly(
        ["test-odood", "--config", temp_dir.join("nowhere").toString,
         "dummy"]);
    assertThrown!OdoodCLIException(cmd.loadProject);
    assertThrown!OdoodCLIException(cmd.maybeLoadProject);

    // Without --config the command falls back to standard discovery.
    cmd = cast(TestConfigCommand) app.parseOnly(["test-odood", "dummy"]);
    cmd.explicitConfigPath.isNull.shouldBeTrue;
}
