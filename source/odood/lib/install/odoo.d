module odood.lib.install.odoo;

private import std.stdio: writeln;
private import std.format: format;
private import std.algorithm.searching: startsWith;
private import std.string: strip;
private import std.exception: enforce;
private import std.conv: to;

private import odood.lib.exception: OdoodException;
private import odood.lib.project.config: ProjectConfig;
private import odood.lib.odoo.serie: OdooSerie;

private import odood.lib.zip;
private import odood.lib.utils;


/** Install odoo to specified project config

    Params:
        config = Project configuration to download Odoo to.
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



void installOdoo(in ProjectConfig config) {
    config.venv_dir.join("bin", "pip").runCmdE([
        "install", "phonenumbers", "python-slugify", "setuptools-odoo",
        "cffi", "jinja2", "python-magic", "Python-Chart"]);

    writeln("Installing odoo dependencies (requirements.txt)");
    config.venv_dir.join("bin", "pip").runCmdE(
        ["install", "-r", config.odoo_path.join("requirements.txt").toString]);

    writeln("Installing odoo to %s".format(config.odoo_path));

    config.venv_dir.join("bin", "python").runCmdE(
        ["setup.py", "develop"],
        config.odoo_path);

}

void installOdooConfig(in ProjectConfig config) {
    import dini;
    import std.array: join;
    Ini odoo_conf;
    Ini odoo_opts = IniSection("options");

    string[] addons_path =[config.odoo_path.join("addons").toString];
    if (config.odoo_serie <= OdooSerie(9)) {
        addons_path ~= config.odoo_path.join("openerp").toString;
    } else {
        addons_path ~= config.odoo_path.join("odoo").toString;
    }
    addons_path ~= config.addons_dir.toString;

    odoo_opts.setKey("addons_path", join(addons_path, ","));
    odoo_opts.setKey("admin_passwd", "admin");
    odoo_opts.setKey("data_dir", config.data_dir.toString);
    odoo_opts.setKey("logfile", config.log_file.toString);
    odoo_opts.setKey("db_host", "localhost");
    odoo_opts.setKey("db_port", "False");
    odoo_opts.setKey("db_user", "odoo");
    odoo_opts.setKey("db_password", "odoo");
    odoo_conf.addSection(odoo_opts);

    odoo_conf.save(config.odoo_conf.toString);
}
