/// Module contains functions to install python for Odood project
module odood.lib.install.python;

private import std.logger;

private import thepath: Path;
private import theprocess: resolveProgram;

private import odood.lib.project: Project;
private import odood.lib.odoo.python;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils: parsePythonVersion;
private import odood.utils.versioned: Version;
private import odood.exception: OdoodException;


/** Find version of system python for specified project.
  * This function will check the version of python required for specified project.
  *
  * Params:
  *     project = instance of Odood project to get version of system python for.
  * Returns: Version version of system python interpreter
  **/
Version getSystemPythonVersion(in Project project) {
    /* If system python is not available, then return version 0.0.0.
     * In this case, system python will not be suitable, and thus
     * Odood will try to build python from sources.
     */
    auto python_interpreter = resolveProgram(project.venv.py_interpreter_name);
    if (python_interpreter.isNull)
        return Version(0, 0, 0);

    return parsePythonVersion(python_interpreter.get);
}


/** Check if system python suitable for specified project.
  **/
bool isSystemPythonSuitable(in Project project) {
    auto sys_py_ver = project.getSystemPythonVersion;
    if (project.odoo.serie <= OdooSerie(10))
        return (sys_py_ver >= Version(2, 7) && sys_py_ver < Version(3));
    if (project.odoo.serie <= OdooSerie(13))
        return (sys_py_ver >= Version(3, 6) && sys_py_ver < Version(3, 9));
    if (project.odoo.serie <= OdooSerie(14))
        return (sys_py_ver >= Version(3, 6) && sys_py_ver < Version(3, 10));
    if (project.odoo.serie <= OdooSerie(16))
        return (sys_py_ver >= Version(3, 7) && sys_py_ver < Version(3, 11));
    if (project.odoo.serie <= OdooSerie(17))
        return (sys_py_ver >= Version(3, 10) && sys_py_ver < Version(3, 12));
    if (project.odoo.serie <= OdooSerie(18))
        return (sys_py_ver >= Version(3, 10) && sys_py_ver < Version(3, 12));

    /// Unknown odoo version
    return false;
}


/** Install virtual env for specified project
  **/
void installVirtualenv(in Project project,
                       in string python_version,
                       in string node_version) {
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
    if (project.odoo.serie > OdooSerie(10))
        project.venv.installPyPackages("setuptools>=45,<58");

    // Install javascript dependecies
    project.venv.installJSPackages("rtlcss");

    // Install lessjs only for versions less then 11
    if (project.odoo.serie <= 11)
        project.venv.installJSPackages("less@3.9.0");
}
