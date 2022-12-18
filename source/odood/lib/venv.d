module odood.lib.venv;

private import thepath: Path;

private import odood.lib.project.config: ProjectConfig;
private import odood.lib.exception: OdoodException;
private import odood.lib.utils: runCmd, runCmdE;


/** Run command in virtual environment
  **/
auto runInVenv(in ProjectConfig config,
               in string[] args,
               in Path workDir = Path(),
               in string[string] env = null) {
    return config.bin_dir.join("run-in-venv").runCmd(args, workDir, env);
}

/** Run command in virtual environment.
  * Raise error on non-zero return code.
  **/
auto runInVenvE(in ProjectConfig config,
               in string[] args,
               in Path workDir = Path(),
               in string[string] env = null) {
    return config.bin_dir.join("run-in-venv").runCmdE(args, workDir, env);
}


/** Install python dependencies in virtual environment
  *
  **/
auto installPyPackages(in ProjectConfig config, in string[] packages...) {
    return config.runInVenvE(["pip", "install"] ~ packages);
}


