module odood.lib.venv;

private import std.logger;
private import std.format: format;
private import std.typecons: Nullable;
private import thepath: Path;

private import odood.lib.project.config: ProjectConfig;
private import odood.lib.exception: OdoodException;
private import odood.lib.utils: runCmd, runCmdE;


const struct VirtualEnv {
    private ProjectConfig _config;

    @disable this();

    /** Construct new venv wrapper for this project
      **/
    this(in ProjectConfig config) {
        _config = config;
    }

    /** Run command in virtual environment
      **/
    auto run(in string[] args,
             in Nullable!Path workDir=Nullable!Path.init,
             in string[string] env=null) {
        tracef(
            "Running command in virtualenv: cmd=%s, work dir=%s, env=%s",
            args, workDir, env);
        return _config.bin_dir.join("run-in-venv").runCmd(args, workDir, env);
    }

    /// ditto
    auto run(in string[] args,
             in Path workDir,
             in string[string] env=null) {
        return run(args, Nullable!Path(workDir), env);
    }

    /** Run command in virtual environment.
      * Raise error on non-zero return code.
      **/
    auto runE(in string[] args,
              in Nullable!Path workDir=Nullable!Path.init,
              in string[string] env=null) {
        tracef(
            "Running command in virtualenv (with exit-code check): " ~
            "cmd=%s, work dir=%s, env=%s",
            args, workDir, env);
        return _config.bin_dir.join("run-in-venv").runCmdE(args, workDir, env);
    }

    /// ditto
    auto runE(in string[] args,
              in Path workDir,
              in string[string] env=null) {
        return runE(args, Nullable!Path(workDir), env);
    }


    /** Install python dependencies in virtual environment
      *
      **/
    auto installPyPackages(in string[] packages...) {
        return pip(["install"] ~ packages);
    }

    /** Install python requirements from requirements.txt file
      *
      **/
    auto installPyRequirements(in Path requirements) {
        return pip("install", "-r", requirements.toString);
    }

    /** Run pip, passing all arguments to pip
      *
      **/
    auto pip(in string[] args...) {
        return runE(["pip"] ~ args);
    }

    /** Run python, passing all arguments to python
      *
      **/
    auto python(in string[] args,
                in Path workDir) {
        return runE(args, workDir);
    }

    /// ditto
    auto python(in string[] args...) {
        return runE(args);
    }

    /** Run npm passing all arguments to npm
      *
      **/
    auto npm(in string[] args...) {
        return runE(["npm"] ~ args);
    }

}
