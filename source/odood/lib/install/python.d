/// Module contains functions to install python for Odood project
module odood.lib.install.python;

private import odood.lib.project_config: ProjectConfig;
private import odood.lib.odoo_serie: OdooSerie;


string guessPythonVersion(in ProjectConfig config) {
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

