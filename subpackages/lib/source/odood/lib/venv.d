module odood.lib.venv;

private import std.logger;
private import std.format: format;
private import std.typecons: Nullable;
private import std.exception: enforce;
private import std.conv: to;
private static import std.process;

private import thepath: Path;
private static import dyaml;

private import odood.lib.exception: OdoodException;
private import odood.lib.theprocess;


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
    this(in ref dyaml.Node config) {
        _path = Path(config["path"].as!string);
        _py_serie = config["python_serie"].as!PySerie;
    }

    /// Path where virtualenv isntalled
    @property @safe pure nothrow const(Path) path() const {return _path;}

    /// Serie of python used for this virtualenv (py2 or py3)
    @property const(PySerie) py_serie() const {return _py_serie;}

    /// Name of python interpreter
    @property const(string) py_interpreter_name() const {
        final switch(_py_serie) {
            case PySerie.py2:
                return "python2";
            case PySerie.py3:
                return "python3";
        }
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
        import std.file: getAttributes, setAttributes;
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
        return run(args, workDir, env, config).ensureStatus();
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
        import std.regex: ctRegex, matchFirst;
        import std.parallelism: totalCPUs;
        import odood.lib.utils: download;

        infof("Building python version %s...", build_version);

        // Compute short python version
        immutable auto re_py_version = ctRegex!(`(\d+).(\d+).(\d+)`);
        auto re_match = build_version.matchFirst(re_py_version);
        enforce!OdoodException(
            !re_match.empty,
            "Cannot parse provided python version '%s'".format(build_version));
        string python_version_major = re_match[1];

        // Create temporary directory to build python
        Path tmp_dir = _path.join("build-python");
        tmp_dir.mkdir(true);
        scope(exit) tmp_dir.remove();

        // Define paths and links to download python
        string python_download_link =
            "https://www.python.org/ftp/python/%s/Python-%s.tgz".format(
                    build_version, build_version);
        auto python_download_path = tmp_dir.join(
            "python-%s.tgz".format(build_version));
        auto python_build_dir = tmp_dir.join(
            "Python-%s".format(build_version));
        auto python_path = _path.join("python");

        // Ensure we can start building process
        enforce!OdoodException(
            !python_path.exists,
            "Python destination path (%s) already exists".format(python_path));
        enforce!OdoodException(
            !python_build_dir.exists,
            "Python build dir (%s) already exists.".format(python_build_dir));

        string[] python_configure_opts = ["--prefix=%s".format(python_path)];

        if (enable_sqlite)
            python_configure_opts ~= "--enable-loadable-sqlite-extensions";

        if (!python_download_path.exists) {
            infof(
                "Downloading python from %s to %s...",
                python_download_link,
                python_download_path);
            download(python_download_link, python_download_path);
        }

        if (!python_build_dir.exists) {
            // Extract only if needed
            info("Unpacking python...");
            Process("tar")
                .withArgs(["-xzf", python_download_path.toString])
                .inWorkDir(tmp_dir)
                .execute()
                .ensureStatus();
        }

        // TODO: Install 'make' and 'libsqlite3-dev' if needed
        //       Possibly have to be added when installation of system packages
        //       will be implemented

        // Configure python build
        info("Running python's configure script...");
        Process(python_build_dir.join("configure"))
            .withArgs(python_configure_opts)
            .inWorkDir(python_build_dir)
            .execute()
            .ensureStatus();

        // Build python itself
        info("Building python...");
        Process("make")
            .withArgs(["--jobs=%s".format(totalCPUs > 1 ? totalCPUs -1 : 1)])
            .inWorkDir(python_build_dir)
            .execute()
            .ensureStatus();

        // Install python
        info("Installing python...");
        Process("make")
            .withArgs([
                "--jobs=%s".format(totalCPUs > 1 ? totalCPUs -1 : 1),
                "install"])
            .inWorkDir(python_build_dir)
            .execute()
            .ensureStatus();

        // Create symlink to 'python' if needed
        if (!python_path.join("bin", "python").exists) {
            tracef(
                "Linking %s to %s",
                python_path.join(
                    "bin", "python%s".format(python_version_major)),
                    python_path.join("bin", "python"));
            python_path.join(
                "bin", "python%s".format(python_version_major)
            ).symlink(python_path.join("bin", "python"));
        }
        if (!python_path.join("bin", "pip").exists) {
            tracef(
                "Linking %s to %s",
                python_path.join(
                    "bin", "pip%s".format(python_version_major)),
                    python_path.join("bin", "pip"));
            python_path.join(
                "bin", "pip%s".format(python_version_major)
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
    void initializeVirtualEnv(in string python_version, in string node_version) {
        import std.parallelism: totalCPUs;

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
                        .ensureStatus();
                    break;
                case PySerie.py3:
                    Process("python3")
                        .withArgs([
                            "-m", "virtualenv",
                            "-p", "python3",
                            _path.toString])
                        .execute()
                        .ensureStatus();
                    break;
            }
        } else {
            buildPython(python_version);
            Process("python3")
                .withArgs([
                    "-m", "virtualenv",
                    "-p", _path.join("python", "bin", "python").toString,
                    _path.toString])
                .execute()
                .ensureStatus();
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
