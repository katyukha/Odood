module odood.lib.odoo.python;

private import odood.lib.venv;
private import odood.lib.project: Project;
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


/** Suggest python version for specified project.
  * This is used to determine what version of python to build.
  * Returns: the suggested python version for specified project.
  **/
string suggestPythonVersion(in Project project) {
    if (project.odoo.serie <= OdooSerie(10))
        return "2.7.18";
    if (project.odoo.serie == OdooSerie(11))
        return "3.7.17";
    if (project.odoo.serie == OdooSerie(12))
        return "3.7.17";
    if (project.odoo.serie == OdooSerie(13))
        return "3.8.17";
    if (project.odoo.serie == OdooSerie(14))
        return "3.8.17";
    if (project.odoo.serie == OdooSerie(15))
        return "3.8.17";
    if (project.odoo.serie == OdooSerie(16))
        return "3.8.17";
    return "3.8.17";
}
