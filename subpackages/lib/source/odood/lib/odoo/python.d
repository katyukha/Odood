module odood.lib.odoo.python;

private import theprocess: resolveProgram;

private import odood.lib.venv;
private import odood.lib.project: Project;
private import odood.utils.odoo.serie;
private import odood.utils.versioned: Version;
private import odood.utils: parsePythonVersion;


/** Guess major python version for specified odoo serie
  *
  * Params:
  *     odoo_serie = odoo versions (serie) to guess python version for
  *
  * Returns: Python's major versions suitable for specified Odoo serie
  **/
PySerie guessPySerie(in OdooSerie odoo_serie) {
    if (odoo_serie < OdooSerie("11")) {
        return PySerie.py2;
    } else {
        return PySerie.py3;
    }
}


/** Suggest python version for specified Odoo serie.
  * This is used to determine what version of python to build.
  * Returns: the suggested python version for specified Odoo serie.
  **/
string suggestPythonVersion(in OdooSerie serie) {
    if (serie <= OdooSerie(10))
        return "2.7.18";
    if (serie == OdooSerie(11))
        return "3.7.17";
    if (serie == OdooSerie(12))
        return "3.7.17";
    if (serie == OdooSerie(13))
        return "3.8.20";
    if (serie == OdooSerie(14))
        return "3.8.20";
    if (serie == OdooSerie(15))
        return "3.10.16";
    if (serie == OdooSerie(16))
        return "3.10.16";
    if (serie == OdooSerie(17))
        return "3.10.16";
    if (serie == OdooSerie(18))
        return "3.10.16";
    return "3.10.16";
}


/** Check if Python version is suitable for specified Odoo serie.
  **/
bool isPythonSuitableForSerie(in Version py_version, in OdooSerie serie) {
    if (serie <= OdooSerie(10))
        return (py_version >= Version(2, 7) && py_version < Version(3));
    if (serie <= OdooSerie(13))
        return (py_version >= Version(3, 6) && py_version < Version(3, 9));
    if (serie <= OdooSerie(14))
        return (py_version >= Version(3, 6) && py_version < Version(3, 10));
    if (serie <= OdooSerie(16))
        return (py_version >= Version(3, 7) && py_version < Version(3, 11));
    if (serie <= OdooSerie(17))
        return (py_version >= Version(3, 10) && py_version < Version(3, 12));
    if (serie <= OdooSerie(18))
        return (py_version >= Version(3, 10) && py_version < Version(3, 12));

    /// Unknown odoo version
    return false;
}


/** Find version of system python for specified project.
  * This function will check the version of python required for specified project.
  *
  * Params:
  *     project = instance of Odood project to get version of system python for.
  * Returns: Version version of system python interpreter
  **/
Version getSystemPythonVersion(in PySerie py_serie) {
    /* If system python is not available, then return version 0.0.0.
     * In this case, system python will not be suitable, and thus
     * Odood will try to build python from sources.
     */
    auto python_interpreter = resolveProgram(py_serie.getPyInterpreterName);
    if (python_interpreter.isNull)
        return Version(0, 0, 0);

    return parsePythonVersion(python_interpreter.get);
}

/// ditto
Version getSystemPythonVersion(in OdooSerie serie) {
    return getSystemPythonVersion(serie.guessPySerie);
}


/** Check if system python suitable for specified project.
  **/
bool isSystemPythonSuitable(in OdooSerie serie) {
    auto sys_py_ver = serie.getSystemPythonVersion;
    return isPythonSuitableForSerie(sys_py_ver, serie);
}

/** Try to automatically detect best virtualenv options for specified project.
  **/
auto guessVenvOptions(in OdooSerie serie) {
    VenvOptions venv_options;
    if (isSystemPythonSuitable(serie))
        venv_options.install_type = PyInstallType.System;
    else {
        version(OSX) {
            venv_options.install_type = PyInstallType.PyEnv;
        } else {
            venv_options.install_type = PyInstallType.Build;
        }
        venv_options.py_version = serie.suggestPythonVersion;
    }
    return venv_options;
}

