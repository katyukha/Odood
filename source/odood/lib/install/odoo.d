module odood.lib.install.odoo;

private import std.logger;
private import std.format: format;
private import std.algorithm.searching: startsWith;
private import std.string: strip;
private import std.exception: enforce;
private import std.conv: to;

private import dini: Ini;

private import odood.lib.exception: OdoodException;
private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;

private import odood.lib.zip;
private import odood.lib.utils;


/** Download Odoo to odoo.path specified by project
  *
  * Params:
  *     project = Project to download Odoo to.
 **/
void installDownloadOdoo(in Project project) {
    // TODO: replace with logger calls, or with colored output.
    import std.stdio;
    auto odoo_archive_path = project.directories.downloads.join(
            "odoo.%s.zip".format(project.odoo.branch));

    enforce!OdoodException(
        project.odoo.repo.startsWith("https://github.com"),
        "Currently, download of odoo is supported only " ~
        "from github repositories.");

    auto download_url = "%s/archive/%s.zip".format(
        project.odoo.repo.strip("", ".git"), project.odoo.branch);

    // TODO: Switch to tar.gz, for smaller archives
    if (!odoo_archive_path.exists) {
        infof(
            "Downloading odoo from %s to %s",
            download_url, odoo_archive_path);
        download(download_url, odoo_archive_path);
    }

    // Extract, with unfloding content of odoo-<branch> to
    // dest folder directly.
    infof(
        "Extracting odoo from %s to %s",
        odoo_archive_path, project.odoo.path);
    extract_zip_archive(
        odoo_archive_path, project.odoo.path,
        "odoo-%s/".format(project.odoo.branch));
}


/** Install Odoo in virtual environment of specified project
  *
  * Params:
  *     project = Project to download Odoo to.
  **/
void installOdoo(in Project project) {
    // Install python dependecnies
    project.venv.installPyPackages(
        "phonenumbers", "python-slugify", "setuptools-odoo",
        "cffi", "jinja2", "python-magic", "Python-Chart", "lodoo");

    info("Installing odoo dependencies (requirements.txt)");
    project.venv.installPyRequirements(
        project.odoo.path.join("requirements.txt"));

    infof("Installing odoo to %s", project.odoo.path);

    project.venv.python(
        ["setup.py", "develop"],
        project.odoo.path);
}


// TODO: Do we need this function?
/** Generate and save Odoo configuration to project
  *
  * Params:
  *     project = Project save odoo config to.
  *     odoo_config = Ini struture that represents desired odoo config
  **/
void installOdooConfig(in Project project, in Ini odoo_config) {
    // Copy provided config. Thus we will have two configs: normal and test.
    Ini odoo_conf = cast(Ini) odoo_config;
    Ini odoo_test_conf = cast(Ini) odoo_config;

    // Save odoo configs
    odoo_conf.save(project.odoo.configfile.toString);

    // Update test config with different xmlrpc/http port to avoid conflicts
    // with running odoo server
    if (project.odoo.serie < OdooSerie(11)) {
        odoo_test_conf["options"].setKey("xmlrpc_port", "8269");
        odoo_test_conf["options"].setKey("longpolling_port", "8272");
    } else {
        odoo_test_conf["options"].setKey("http_port", "8269");
        odoo_test_conf["options"].setKey("longpolling_port", "8272");
    }

    // Disable logfile for test config, to enforce log to
    // stdout/stderr for tests
    odoo_test_conf["options"].setKey("logfile", "False");

    // Save test odoo config
    odoo_test_conf.save(project.odoo.testconfigfile.toString);

}
