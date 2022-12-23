/// Module contains functions to install python for Odood project
module odood.lib.install.python;

private import semver;
private import thepath: Path;

private import std.regex: ctRegex, matchFirst;
private import std.exception: enforce;
private import std.format: format;
private import std.parallelism: totalCPUs;
private import std.conv: to;

private import odood.lib.project.config: ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.exception: OdoodException;
private import odood.lib.utils: runCmd, runCmdE, download;


// Define template for simple script that allows to run any command in
// python's virtualenv
private immutable string SCRIPT_RUN_IN_ENV="#!/usr/bin/env bash
source \"%s\";
exec \"$@\"; res=$?;
deactivate;
exit $res;
";


/// Guess major python version to run this project
ubyte guessPythonMajorVersion(in ProjectConfig config) {
    if (config.odoo_serie < OdooSerie("11")) {
        return 2;
    } else {
        return 3;
    }
}


/** Guess python interpreter name.
  * This method is used to get name of python executable
  * for this version of odoo.
  **/
string guessPythonInterpreter(in ProjectConfig config) {
    return "python%s".format(config.guessPythonMajorVersion);
}


/** Find version of system python
  * Returns: SemVer version of system python interpreter
  **/
SemVer getSystemPythonVersion(in ProjectConfig config) {
    import std.process: execute;

    auto python_interpreter = config.guessPythonInterpreter;
    auto res = execute([python_interpreter, "--version"]);
    enforce!OdoodException(
        res.status == 0,
        "Cannot get version of python interpreter '%s'".format(python_interpreter));

    auto re_py_version = ctRegex!(`Python (\d+.\d+.\d+)`);
    auto re_match = res.output.matchFirst(re_py_version);
    enforce!OdoodException(
        !re_match.empty,
        "Cannot parse system python's version '%s'".format(res.output));
    return SemVer(re_match[1]);
}


/// Is system python suitable for specified project config
bool isSystemPythonSuitable(in ProjectConfig config) {
    auto sys_py_ver = config.getSystemPythonVersion;
    if (config.odoo_serie <= OdooSerie(10))
        return (sys_py_ver >= SemVer(2, 7) && sys_py_ver < SemVer(3));
    if (config.odoo_serie <= OdooSerie(12))
        return (sys_py_ver >= SemVer(3, 6) && sys_py_ver < SemVer(3, 9));
    if (config.odoo_serie <= OdooSerie(14))
        return (sys_py_ver >= SemVer(3, 6) && sys_py_ver < SemVer(3, 10));
    if (config.odoo_serie <= OdooSerie(16))
        return (sys_py_ver >= SemVer(3, 7) && sys_py_ver < SemVer(3, 11));

    /// Unknown odoo version
    return false;
}


/** Suggest python version for specified project configuration.
  * This is used to determine what version of python to build.
  * Returns: the suggested python version for specified project config.
  **/
string suggestPythonVersion(in ProjectConfig config) {
    if (config.odoo_serie <= OdooSerie(10)) {
        return "2.7.18";
    } else if (config.odoo_serie == OdooSerie(11)) {
        return "3.7.13";
    } else if (config.odoo_serie == OdooSerie(12)) {
        return "3.7.13";
    } else if (config.odoo_serie == OdooSerie(13)) {
        return "3.8.13";
    } else if (config.odoo_serie == OdooSerie(14)) {
        return "3.8.13";
    } else if (config.odoo_serie == OdooSerie(15)) {
        return "3.8.13";
    } else if (config.odoo_serie == OdooSerie(16)) {
        return "3.8.13";
    } else {
        return "3.8.13";
    }
}


/** Build python

    Params:
        config = project configuration
        enable_sqlite = if set, then build with SQLite3 support
  **/
void buildPython(in ProjectConfig config,
                 in bool enable_sqlite=false) {
    string build_version = config.python_version;
    if (!build_version) {
        build_version = config.suggestPythonVersion;
    }

    // Compute short python version
    auto re_py_version = ctRegex!(`(\d+).(\d+).(\d+)`);
    auto re_match = build_version.matchFirst(re_py_version);
    enforce!OdoodException(
        !re_match.empty,
        "Cannot parse provided python version '%s'".format(build_version));
    string python_version_short = re_match[1];

    string python_download_link =
        "https://www.python.org/ftp/python/%s/Python-%s.tgz".format(
                build_version, build_version);
    auto python_download_path = config.downloads_dir.join(
        "python-%s.tgz".format(build_version));
    auto python_build_dir = config.downloads_dir.join(
        "Python-%s".format(build_version));
    auto python_path = config.project_root.join("python");

    enforce!OdoodException(
        !python_path.exists,
        "Python destination path (%s) already exists".format(python_path));
    //enforce!OdoodException(
        //!python_build_dir.exists,
        //"Python build dir (%s) already exists.".format(python_build_dir));

    string[] python_configure_opts = ["--prefix=%s".format(python_path)];

    if (enable_sqlite)
        python_configure_opts ~= "--enable-loadable-sqlite-extensions";

    if (!python_download_path.exists) {
        download(python_download_link, python_download_path);
    }

    if (!python_build_dir.exists) {
        // Extract only if needed
        runCmdE(
            ["tar", "-xzf", python_download_path.toString],
            config.downloads_dir.toString);
    }

    // TODO: Install 'make' and 'libsqlite3-dev' if needed
    //       Possibly have to be added when installation of system packages
    //       will be implemented

    // Configure python build
    python_build_dir.join("configure").runCmdE(
        python_configure_opts,
        python_build_dir);

    // Build python itself
    runCmdE(
        ["make", "--jobs=%s".format(totalCPUs > 1 ? totalCPUs -1 : 1)],
        python_build_dir.toString);

    // Install python
    runCmdE(
        ["make",
         "--jobs=%s".format(totalCPUs > 1 ? totalCPUs -1 : 1),
         "install"],
        python_build_dir.toString);

    // Remove downloaded python
    python_download_path.remove();
    python_build_dir.remove();

    // Create symlink to 'python' if needed
    if (!python_path.join("bin", "python").exists) {
        python_path.join(
            "bin", "python%s".format(python_version_short)
        ).symlink(python_path.join("bin", "python"));
    }
    if (!python_path.join("bin", "pip").exists) {
        python_path.join(
            "bin", "pip%s".format(python_version_short)
        ).symlink(python_path.join("bin", "pip"));
    }
}


/** Install virtual env for specified project config
  **/
void installVirtualenv(in ProjectConfig config) {
    import std.stdio: writeln;
    import std.parallelism: totalCPUs;
    import odood.lib.install.python;

    writeln("Installing virtualenv...");

    if (isSystemPythonSuitable(config)){
        runCmdE([
            "python3",
            "-m", "virtualenv",
            "-p", config.guessPythonInterpreter,
            config.venv_dir.toString]);
    } else {
        buildPython(config);
        writeln(
            "%s successfully built".format(
                runCmdE(
                    config.project_root.join("python", "bin", config.guessPythonInterpreter),
                    ["--version"]).output));
        runCmdE([
            "python3",
            "-m", "virtualenv",
            "-p", config.project_root.join(
                "python", "bin", config.guessPythonInterpreter).toString,
            config.venv_dir.toString]);
    }

    // Add bash script to run any command in virtual env
    import std.file: getAttributes, setAttributes;
    import std.conv : octal;
    config.bin_dir.join("run-in-venv").writeFile(
        SCRIPT_RUN_IN_ENV.format(
            config.venv_dir.join("bin", "activate")));
    config.bin_dir.join("run-in-venv").setAttributes(octal!755);

    // Use correct version of setuptools, because some versions of Odoo
    // required 'use_2to3' option, that is removed in latest versions
    if (config.odoo_serie > OdooSerie(10)) {
        config.venv.installPyPackages("setuptools>=45,<58");
    }

    // Install nodeenv and node
    config.venv.installPyPackages("nodeenv");
    config.venv.runE([
        "nodeenv", "--python-virtualenv", "--clean-src",
        "--jobs", totalCPUs.to!string, "--node", config.node_version,
    ]);
    config.venv.npm("set", "user", "0");
    config.venv.npm("set", "unsafe-perm", "true");

    // Install javascript dependecies
    // TODO: Make it optional, install automatically only for odoo <= 11
    config.venv.npm("install", "-g", "less@3.9.0", "rtlcss");
}

