/// Module contains functions to install python for Odood project
module odood.lib.install.python;

private import semver;
private import thepath: Path;

private import std.regex: ctRegex, matchFirst;
private import std.exception: enforce;
private import std.format: format;
private import std.parallelism: totalCPUs;
private import std.conv: to;
private import std.logger;

private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.exception: OdoodException;
private import odood.lib.utils: download;
private import odood.lib.venv: PySerie;
private import odood.lib.theprocess;


/** Find version of system python for specified project.
  * This function will check the version of python required for specified project.
  *
  * Params:
  *     project = instance of Odood project to get version of system python for.
  * Returns: SemVer version of system python interpreter
  **/
SemVer getSystemPythonVersion(in Project project) {
    import std.process: environment;
    import std.path: pathSplitter;

    /* If system python is not available, then return version 0.0.0.
     * In this case, system python will not be suitable, and thus
     * Odood will try to build python from sources.
     */
    if (resolveProgram(project.venv.py_interpreter_name).isNull)
        return SemVer(0, 0, 0);

    auto python_interpreter = project.venv.py_interpreter_name;
    auto python_version_raw = Process(python_interpreter)
        .withArgs("--version")
        .execute()
        .ensureStatus(
            "Cannot get version of python interpreter '%s'".format(
                python_interpreter))
        .output;

    immutable auto re_py_version = ctRegex!(`Python (\d+.\d+.\d+)`);
    auto re_match = python_version_raw.matchFirst(re_py_version);
    enforce!OdoodException(
        !re_match.empty,
        "Cannot parse system python's version '%s'".format(python_version_raw));
    return SemVer(re_match[1]);
}


/** Check if system python suitable for specified project.
  **/
bool isSystemPythonSuitable(in Project project) {
    auto sys_py_ver = project.getSystemPythonVersion;
    if (project.odoo.serie <= OdooSerie(10))
        return (sys_py_ver >= SemVer(2, 7) && sys_py_ver < SemVer(3));
    if (project.odoo.serie <= OdooSerie(12))
        return (sys_py_ver >= SemVer(3, 6) && sys_py_ver < SemVer(3, 9));
    if (project.odoo.serie <= OdooSerie(14))
        return (sys_py_ver >= SemVer(3, 6) && sys_py_ver < SemVer(3, 10));
    if (project.odoo.serie <= OdooSerie(16))
        return (sys_py_ver >= SemVer(3, 7) && sys_py_ver < SemVer(3, 11));

    /// Unknown odoo version
    return false;
}


// TODO: move to odoo/python ?
/** Suggest python version for specified project.
  * This is used to determine what version of python to build.
  * Returns: the suggested python version for specified project.
  **/
string suggestPythonVersion(in Project project) {
    if (project.odoo.serie <= OdooSerie(10)) {
        return "2.7.18";
    } else if (project.odoo.serie == OdooSerie(11)) {
        return "3.7.13";
    } else if (project.odoo.serie == OdooSerie(12)) {
        return "3.7.13";
    } else if (project.odoo.serie == OdooSerie(13)) {
        return "3.8.13";
    } else if (project.odoo.serie == OdooSerie(14)) {
        return "3.8.13";
    } else if (project.odoo.serie == OdooSerie(15)) {
        return "3.8.13";
    } else if (project.odoo.serie == OdooSerie(16)) {
        return "3.8.13";
    } else {
        return "3.8.13";
    }
}


/** Install virtual env for specified project
  **/
void installVirtualenv(in Project project,
                       in string python_version,
                       in string node_version) {
    import std.parallelism: totalCPUs;
    import odood.lib.install.python;

    if (python_version == "auto") {
        if (isSystemPythonSuitable(project))
            project.venv.initializeVirtualEnv("system", node_version);
        else
            project.venv.initializeVirtualEnv(
                project.suggestPythonVersion,
                node_version);
    } else {
        project.venv.initializeVirtualEnv(python_version, node_version);
    }


    // Use correct version of setuptools, because some versions of Odoo
    // required 'use_2to3' option, that is removed in latest versions
    if (project.odoo.serie > OdooSerie(10)) {
        project.venv.installPyPackages("setuptools>=45,<58");
    }

    // Install javascript dependecies
    // TODO: Make it optional, install automatically only for odoo <= 11
    project.venv.installJSPackages("less@3.9.0", "rtlcss");
}
