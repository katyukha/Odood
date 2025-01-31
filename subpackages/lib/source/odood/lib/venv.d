module odood.lib.venv;

private import std.logger;
private import std.format: format;
private import std.typecons: Nullable;
private import std.exception: enforce;
private import std.conv: to;
private import std.parallelism: totalCPUs;
private import std.regex: ctRegex, matchFirst;

private static import std.process;

private import thepath: Path;
private static import dyaml;

private import odood.exception: OdoodException;
private import theprocess;
private import odood.utils;
private import odood.utils.versioned: Version;

// TOOD: May be it have sense to move this to utils subpackage.

// Define template for simple script that allows to run any command in
// python's virtualenv
private immutable string SCRIPT_RUN_IN_ENV="#!/usr/bin/env bash
source \"%s\";
exec \"$@\"; res=$?;
deactivate;
exit $res;
";


/// Python major version
enum PySerie {
    py2=2,
    py3=3,
}

/* TODO: move to utils package?
 *       Dyaml integration should be kept in lib
 */

/** VirtualEnv wrapper, to simplify operations within virtual environment
  *
  **/
const struct VirtualEnv {
    /// Virtual environment directory
    private const Path _path;

    /// Python serie for this virtualenv
    private const PySerie _py_serie;

    @disable this();

    /** Construct new venv wrapper for this project
      **/
    this(in Path path, in PySerie py_serie) {
        _path = path;
        _py_serie = py_serie;
    }

    /** Constrcut virtualenv from yaml node
      **/
    this(in dyaml.Node config) {
        _path = Path(config["path"].as!string);
        _py_serie = config["python_serie"].as!PySerie;
    }

    /// Path where virtualenv isntalled
    @safe pure nothrow const(Path) path() const { return _path; }

    /// Bin path inside this virtualenv
    @safe pure nothrow const(Path) bin_path() const {return _path.join("bin"); }

    /// Serie of python used for this virtualenv (py2 or py3)
    @safe const(PySerie) py_serie() const { return _py_serie; }

    /// Name of python interpreter
    @safe const(string) py_interpreter_name() const {
        final switch(_py_serie) {
            case PySerie.py2:
                return "python2";
            case PySerie.py3:
                return "python3";
        }
    }

    /// Python version for this venv
    @safe auto py_version() const {
        return parsePythonVersion(_path.join("bin", py_interpreter_name));
    }

    package dyaml.Node toYAML() const {
        return dyaml.Node([
            "path": dyaml.Node(_path.toString),
            "python_serie": dyaml.Node(_py_serie),
        ]);
    }

    /// Initialize run-in-venv script
    private void initRunInVenvScript() const {
        // Add bash script to run any command in virtual env
        import std.file: setAttributes;
        import std.conv : octal;
        _path.join("bin", "run-in-venv").writeFile(
            SCRIPT_RUN_IN_ENV.format(
                _path.join("bin", "activate")));
        _path.join("bin", "run-in-venv").setAttributes(octal!755);
    }

    /** Create run-in-env script if it does not exists yet.
      **/
    void ensureRunInVenvExists() const {
        if (!_path.join("bin", "run-in-venv").exists)
            initRunInVenvScript();
    }

    auto runner() const {
        return Process(_path.join("bin", "run-in-venv"));
    }

    /** Run command in virtual environment
      **/
    auto run(
            in string[] args,
            in Nullable!Path workDir=Nullable!Path.init,
            in string[string] env=null,
            std.process.Config config = std.process.Config.none) {
        tracef(
            "Running command in virtualenv: cmd=%s, work dir=%s, env=%s",
            args, workDir, env);
        auto process = runner();
        if (args.length > 0) process.setArgs(args);
        if (!workDir.isNull) process.setWorkDir(workDir.get);
        if (env) process.setEnv(env);
        if (config != std.process.Config.none) process.setConfig(config);
        return process.execute();
    }

    /// ditto
    auto run(
            in string[] args,
            in Path workDir,
            in string[string] env=null,
            std.process.Config config = std.process.Config.none) {
        return run(args, Nullable!Path(workDir), env, config);
    }

    /// ditto
    auto run(
            in Path path,
            in string[] args,
            in Path workDir,
            in string[string] env=null,
            std.process.Config config = std.process.Config.none) {
        return run([path.toString] ~ args,  workDir, env, config);
    }

    /** Run command in virtual environment.
      * Raise error on non-zero return code.
      **/
    auto runE(
            in string[] args,
            in Nullable!Path workDir=Nullable!Path.init,
            in string[string] env=null,
            std.process.Config config = std.process.Config.none) {
        return run(args, workDir, env, config).ensureStatus(true);
    }

    /// ditto
    auto runE(
            in string[] args,
            in Path workDir,
            in string[string] env=null,
            std.process.Config config = std.process.Config.none) {
        return runE(args, Nullable!Path(workDir), env, config);
    }

    /// ditto
    auto runE(
            in Path path,
            in string[] args,
            in Path workDir,
            in string[string] env=null,
            std.process.Config config = std.process.Config.none) {
        return runE([path.toString] ~ args,  workDir, env, config);
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
        return runE(["python"] ~ args, workDir);
    }

    /// ditto
    auto python(in string[] args...) {
        return runE(["python"] ~ args);
    }

    /** Run npm passing all arguments to npm
      *
      **/
    auto npm(in string[] args...) {
        return runE(["npm"] ~ args);
    }

    /** Install JS dependencies
      *
      **/
    auto installJSPackages(in string[] packages...) {
        return npm(["install", "-g"] ~ packages);
    }

    /** Build python

        Params:
            build_version = version of python to build
            enable_sqlite = if set, then build with SQLite3 support
      **/
    void buildPython(in string build_version,
                     in bool enable_sqlite=false) {
        // Convert string representation of version into Version instance
        // for further processing
        buildPython(Version(build_version), enable_sqlite);
    }

    /// ditto
    void buildPython(in Version build_version,
                     in bool enable_sqlite=false,
                     in bool enable_optimizations=false) {

        infof("Building python version %s...", build_version);

        enforce!OdoodException(
            build_version.isValid && build_version.isStable,
            "Cannot parse provided python version '%s'.".format(build_version));

        // Create temporary directory to build python
        Path tmp_dir = _path.join("build-python");
        tmp_dir.mkdir(true);
        scope(exit) tmp_dir.remove();

        // Define paths and links to download python
        string python_download_link =
            "https://www.python.org/ftp/python/%s/Python-%s.tar.xz".format(
                    build_version, build_version);
        auto python_download_path = getCacheDir("python", tmp_dir).join(
            "python-%s.tgz".format(build_version));
        auto python_src_dir = tmp_dir.join(
            "Python-%s".format(build_version));
        auto python_build_dir = tmp_dir.join(
            "build");
        auto python_path = _path.join("python");

        // Ensure we can start building process
        enforce!OdoodException(
            !python_path.exists,
            "Python destination path (%s) already exists".format(python_path));
        enforce!OdoodException(
            !python_src_dir.exists,
            "Python sources dir (%s) already exists.".format(python_src_dir));

        string[] python_configure_opts = [
            "--prefix=%s".format(python_path),
            "--srcdir=%s".format(python_src_dir),
        ];

        if (enable_sqlite)
            python_configure_opts ~= "--enable-loadable-sqlite-extensions";

        if (enable_optimizations)
            python_configure_opts ~= "--enable-optimizations";

        if (!python_download_path.exists) {
            infof(
                "Downloading python from %s to %s...",
                python_download_link,
                python_download_path);
            download(python_download_link, python_download_path);
        }

        if (!python_src_dir.exists) {
            // Extract only if needed
            info("Unpacking python...");
            Process("tar")
                .withArgs(["-xf", python_download_path.toString])
                .inWorkDir(tmp_dir)
                .execute()
                .ensureStatus(true);
        }

        // Ensure build dir exists
        python_build_dir.mkdir(true);

        // Configure python build
        info("Running python's configure script...");
        Process(python_src_dir.join("configure"))
            .withArgs(python_configure_opts)
            .inWorkDir(python_build_dir)
            .execute()
            .ensureOk(true);

        // Build python itself
        info("Building python...");
        Process("make")
            .withArgs(["--jobs=%s".format(totalCPUs > 1 ? totalCPUs -1 : 1)])
            .inWorkDir(python_build_dir)
            .execute()
            .ensureStatus(true);

        // Install python
        info("Installing python...");
        Process("make")
            .withArgs([
                "--jobs=%s".format(totalCPUs > 1 ? totalCPUs -1 : 1),
                "install"])
            .inWorkDir(python_build_dir)
            .execute()
            .ensureStatus(true);

        // Create symlink to 'python' if needed
        if (!python_path.join("bin", "python").exists &&
                python_path.join("bin", "python%s".format(
                        build_version.major)).exists) {
            tracef(
                "Linking %s to %s",
                python_path.join(
                    "bin", "python%s".format(build_version.major)),
                    python_path.join("bin", "python"));
            python_path.join(
                "bin", "python%s".format(build_version.major)
            ).symlink(python_path.join("bin", "python"));
        }

        // Install pip if needed
        if (!python_path.join("bin", "pip").exists &&
                !python_path.join("bin", "pip%s".format(
                        build_version.major)).exists) {
            infof("Installing pip for just installed python...");

            immutable auto url_get_pip_py = build_version < Version(3, 7) ?
                "https://bootstrap.pypa.io/pip/%s.%s/get-pip.py".format(
                        build_version.major,
                        build_version.minor) :
                "https://bootstrap.pypa.io/pip/get-pip.py";
            tracef("Downloading get-pip.py from %s", url_get_pip_py);
            download(
                url_get_pip_py,
                tmp_dir.join("get-pip.py"));
            Process(python_path.join("bin", "python"))
                .withArgs(tmp_dir.join("get-pip.py").toString)
                .inWorkDir(python_path)
                .execute()
                .ensureStatus(true);
        }

        // Create symlink for 'pip' if needed
        if (!python_path.join("bin", "pip").exists &&
                python_path.join("bin", "pip%s".format(
                        build_version.major)).exists) {
            tracef(
                "Linking %s to %s",
                python_path.join(
                    "bin", "pip%s".format(build_version.major)),
                    python_path.join("bin", "pip"));
            python_path.join(
                "bin", "pip%s".format(build_version.major)
            ).symlink(python_path.join("bin", "pip"));
        }
    }

    /** Initialize virtualenv.
      *
      * Params:
      *     python_version = Python version to install.
      *         Could be one of "system" or "X.Y.Z", where X.Y.Z represents
      *         specific python version to build.
      *     node_version = NodeJS version to install.
      **/
    void initializeVirtualEnv(
            in string python_version,
            in string node_version) {
        info("Installing virtualenv...");

        if (python_version == "system") {
            final switch(_py_serie) {
                case PySerie.py2:
                    Process("python3")
                        .withArgs([
                            "-m", "virtualenv",
                            "-p", "python2",
                            _path.toString])
                        .execute()
                        .ensureStatus(true);
                    break;
                case PySerie.py3:
                    Process("python3")
                        .withArgs([
                            "-m", "virtualenv",
                            "-p", "python3",
                            _path.toString])
                        .execute()
                        .ensureStatus(true);
                    break;
            }
        } else {
            /* TODO: Think about using pyenv, when it is installed
             *       Especially on MacOS
             *
             *       For example:
             *       $ pyenv install 3.10.16
             *       $ $(pyenv prefix 3.10.16)/bin/python -m venv ./venv
             */
            buildPython(python_version);

            // Install virtualenv inside built python environment
            Process(_path.join("python", "bin", "pip"))
                .withArgs("install", "virtualenv")
                .execute()
                .ensureStatus(true);

            // Initialize virtualenv inside built python env
            Process(_path.join("python", "bin", "python"))
                .withArgs([
                    "-m", "virtualenv",
                    "-p", _path.join("python", "bin", "python").toString,
                    _path.toString])
                .execute()
                .ensureStatus(true);
        }

        //// Add bash script to run any command in virtual env
        initRunInVenvScript();

        // Install nodeenv and node
        infof("Installing nodejs version %s", node_version);
        installPyPackages("nodeenv");
        runE([
            "nodeenv", "--python-virtualenv", "--clean-src",
            "--jobs", totalCPUs.to!string, "--node", node_version,
        ]);

        info("VirtualEnv initialized successfully!");
    }
}
