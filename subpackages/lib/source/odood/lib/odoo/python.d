module odood.lib.odoo.python;

private import odood.lib.venv;
private import odood.utils.odoo.serie;


/// Guess major python version for specified odoo serie
PySerie guessPySerie(in OdooSerie odoo_serie) {
    if (odoo_serie < OdooSerie("11")) {
        return PySerie.py2;
    } else {
        return PySerie.py3;
    }
}

