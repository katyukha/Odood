module odood.lib.install.odoo;

private import std.stdio: writeln;
private import std.format: format;
private import std.algorithm.searching: startsWith;
private import std.string: strip;
private import std.exception: enforce;
private import std.conv: to;

private import dini: Ini;

private import odood.lib.exception: OdoodException;
private import odood.lib.project.config: ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;

private import odood.lib.zip;
private import odood.lib.utils;


/** Download Odoo to odoo_path specified by project config
  *
  * Params:
  *     config = Project configuration to download Odoo to.
 **/
void installDownloadOdoo(in ProjectConfig config) {
    // TODO: replace with logger calls, or with colored output.
    import std.stdio;
    auto odoo_archive_path = config.downloads_dir.join(
            "odoo.%s.zip".format(config.odoo_branch));

    enforce!OdoodException(
        config.odoo_repo.startsWith("https://github.com"),
        "Currently, download of odoo is supported only " ~
        "from github repositories.");

    auto download_url = "%s/archive/%s.zip".format(
        config.odoo_repo.strip("", ".git"), config.odoo_branch);

    // TODO: Switch to tar.gz, for smaller archives
    if (!odoo_archive_path.exists) {
        writeln("Downloading odoo from %s to %s".format(
            download_url,
            odoo_archive_path));
        download(download_url, odoo_archive_path);
    }

    // Extract, with unfloding content of odoo-<branch> to
    // dest folder directly.
    writeln("Extracting odoo from %s to %s".format(
        odoo_archive_path, config.odoo_path));
    extract_zip_archive(
        odoo_archive_path, config.odoo_path,
        "odoo-%s/".format(config.odoo_branch));
}


/** Install Odoo in virtual environment of specified project config
  *
  * Params:
  *     config = Project configuration to download Odoo to.
  **/
void installOdoo(in ProjectConfig config) {
    // Install python dependecnies
    config.venv.installPyPackages(
        "phonenumbers", "python-slugify", "setuptools-odoo",
        "cffi", "jinja2", "python-magic", "Python-Chart", "lodoo");

    writeln("Installing odoo dependencies (requirements.txt)");
    config.venv.installPyRequirements(
        config.odoo_path.join("requirements.txt"));

    writeln("Installing odoo to %s".format(config.odoo_path));

    config.venv.python(
        ["setup.py", "develop"],
        config.odoo_path);
}


/** Generate and save Odoo configuration (normal and test) to project
  * specified by project config
  *
  * Params:
  *     config = Project configuration to download Odoo to.
  *     odoo_config = Ini struture that represents desired odoo config
  **/
void installOdooConfig(in ProjectConfig config, in Ini odoo_config) {
    // Copy provided config. Thus we will have two configs: normal and test.
    Ini odoo_conf = cast(Ini) odoo_config;
    Ini odoo_test_conf = cast(Ini) odoo_config;

    // Save odoo configs
    odoo_conf.save(config.odoo_conf.toString);

    // Update test config with different xmlrpc/http port to avoid conflicts
    // with running odoo server
    if (config.odoo_serie < OdooSerie(11)) {
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
    odoo_test_conf.save(config.odoo_test_conf.toString);
}
