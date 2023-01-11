module odood.lib.install.odoo;

private import std.logger;
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
        infof(
            "Downloading odoo from %s to %s",
            download_url, odoo_archive_path);
        download(download_url, odoo_archive_path);
    }

    // Extract, with unfloding content of odoo-<branch> to
    // dest folder directly.
    infof(
        "Extracting odoo from %s to %s",
        odoo_archive_path, config.odoo_path);
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

    info("Installing odoo dependencies (requirements.txt)");
    config.venv.installPyRequirements(
        config.odoo_path.join("requirements.txt"));

    infof("Installing odoo to %s", config.odoo_path);

    config.venv.python(
        ["setup.py", "develop"],
        config.odoo_path);
}


// TODO: Do we need this function?
/** Generate and save Odoo configuration to project
  * specified by project config
  *
  * Params:
  *     config = Project configuration to download Odoo to.
  *     odoo_config = Ini struture that represents desired odoo config
  **/
void installOdooConfig(in ProjectConfig config, in Ini odoo_config) {
    // Copy provided config. Thus we will have two configs: normal and test.
    Ini odoo_conf = cast(Ini) odoo_config;

    // Save odoo configs
    odoo_conf.save(config.odoo_conf.toString);
}
