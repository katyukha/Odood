module odood.lib.install;

private import std.format: format;
private import std.algorithm.searching: startsWith;
private import std.string: strip;
private import std.exception: enforce;
private import std.net.curl: download;

private import odood.lib.exception: OdoodException;
private import odood.lib.project_config: ProjectConfig;

private import odood.lib.zip;


/** Initialize project directory structure for specified project config.
    This function will create all needed directories for project.

    Params:
        config = Project configuration to initialize directory structure.
 **/
void initializeProjectDirs(in ProjectConfig config) {
    config.root_dir.mkdir(true);
    config.conf_dir.mkdir(true);
    config.log_dir.mkdir(true);
    config.downloads_dir.mkdir(true);
    config.addons_dir.mkdir(true);
    config.data_dir.mkdir(true);
    config.backups_dir.mkdir(true);
    config.repositories_dir.mkdir(true);
}


/** Install odoo to specified project config
 **/
void installDownloadOdoo(in ProjectConfig config) {
    import std.stdio;
    import std.format;
    auto odoo_archive_path = config.downloads_dir.join(
            "odoo.%s.zip".format(config.odoo_branch));

    enforce!OdoodException(
        config.odoo_repo.startsWith("https://github.com"),
        "Currently, download of odoo is supported only " ~
        "from github repositories.");

    auto download_url = "%s/archive/%s.zip".format(
        config.odoo_repo.strip("", ".git"), config.odoo_branch);

    // TODO: Add timeout
    // TODO: Switch to tar.gz, for smaller archives
    if (!odoo_archive_path.exists) {
        writeln("Downloading odoo from %s to %s".format(
            download_url,
            odoo_archive_path));
        download(download_url, odoo_archive_path.toString);
    }

    // Extract, with unfloding content of odoo-<branch> to
    // dest folder directly.
    writeln("Extracting odoo from %s to %s".format(
        odoo_archive_path, config.odoo_path));
    extract_zip_archive(
        odoo_archive_path, config.odoo_path,
        "odoo-%s/".format(config.odoo_branch));
}





