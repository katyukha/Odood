/// Module contains functions to install python for Odood project
module odood.project.install.python;

private import std.logger;

private import thepath: Path;
private import theprocess: resolveProgram;
private import versioned: Version;

private import odood.project: Project;
private import odood.lib.python.odoo;
private import odood.lib.python.venv: PyInstallType, VenvOptions;
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
    } else if (project.odoo.serie >= OdooSerie(16) && project.odoo.serie < OdooSerie(19)) {
        // This is fix, for recent update of python package zope.index (5.1), that is used by gevent and that breaks odoo startup.
        // Lower bound raised to 78.1.1 to fix CVE-2025-47273 (path traversal
        // in setuptools' PackageIndex); still capped below 81 to keep the
        // deprecated-but-required pkg_resources behaviour.
        infof("Enforce setuptools version between 78.1.1 and 81 to correctly handle pkg_resources (that is deprecated but still used), and to fix CVE-2025-47273");
        project.venv.installPyPackages("setuptools>=78.1.1,<81");
    } else if (project.odoo.serie >= OdooSerie(19)) {
        // Ensure that we use recent version of setuptools
        // Use the latest setuptools (>=83.0.0). This also covers CVE-2025-47273
        // (path traversal in setuptools' PackageIndex), fixed in 78.1.1.
        infof("Enforce latest setuptools version (>=83.0.0, also fixes CVE-2025-47273)");
        project.venv.installPyPackages("setuptools>=83.0.0");
    }

    // Install javascript dependecies
    project.venv.installJSPackages("rtlcss");

    // Install lessjs only for versions less then 11
    if (project.odoo.serie <= 11)
        project.venv.installJSPackages("less@3.9.0");
}
