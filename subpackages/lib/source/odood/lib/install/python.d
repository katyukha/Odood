/// Module contains functions to install python for Odood project
module odood.lib.install.python;

private import std.logger;

private import thepath: Path;
private import theprocess: resolveProgram;
private import versioned: Version;

private import odood.lib.project: Project;
private import odood.lib.odoo.python;
private import odood.lib.venv: PyInstallType, VenvOptions;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils: parsePythonVersion;
private import odood.exception: OdoodException;



/** Install virtual env for specified project
  **/
void installVirtualenv(in Project project,
                       in VenvOptions venv_options) {
    // Initialize virtualenv for this project
    project.venv.initializeVirtualEnv(venv_options);

    // Use correct version of setuptools, because some versions of Odoo
    // required 'use_2to3' option, that is removed in latest versions
    if (project.odoo.serie > OdooSerie(10) && project.odoo.serie < OdooSerie(16)) {
        infof("Enforce setuptools version between 45 and 58: because some modules in older Odoo versions may require pythons 2to3 tool, that is removed in later versions.");
        project.venv.installPyPackages("setuptools>=45,<58");
    }

    // Install javascript dependecies
    project.venv.installJSPackages("rtlcss");

    // Install lessjs only for versions less then 11
    if (project.odoo.serie <= 11)
        project.venv.installJSPackages("less@3.9.0");
}
