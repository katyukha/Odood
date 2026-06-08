module odood.lib.python.odoo;

private import theprocess: resolveProgram;
private import versioned: Version;

private import odood.lib.python.venv: PySerie, PyInstallType, VenvOptions,
    getSystemPythonVersion;
private import odood.utils.odoo.serie;


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
        return "3.10.20";
    if (serie == OdooSerie(16))
        return "3.10.20";
    if (serie == OdooSerie(17))
        return "3.11.15";
    if (serie == OdooSerie(18))
        return "3.12.13";
    if (serie == OdooSerie(19))
        return "3.12.13";
    return "3.12.13";
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
    if (serie <= OdooSerie(19))
        return (py_version >= Version(3, 10) && py_version < Version(3, 13));

    /// Unknown odoo version
    return false;
}


/** Find version of system python for specified Odoo serie.
  *
  * Params:
  *     serie = Odoo serie to get system python version for
  * Returns: Version of system python interpreter
  **/
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
        venv_options.install_type = PyInstallType.Build;
        venv_options.py_version = serie.suggestPythonVersion;
    }
    return venv_options;
}
