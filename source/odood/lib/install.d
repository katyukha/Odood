module odood.lib.install;

private import std.stdio: writeln;
private import std.format: format;
private import std.algorithm.searching: startsWith;
private import std.string: strip;
private import std.exception: enforce;
private import std.net.curl: download;
private import std.conv: to;

private import odood.lib.exception: OdoodException;
private import odood.lib.project_config: ProjectConfig;

private import odood.lib.zip;
private import odood.lib.utils;


// Define template for simple script that allows to run any command in
// python's virtualenv
private string SCRIPT_RUN_IN_ENV="#!/usr/bin/env bash
source \"%s\";
\"$@\"; res=$?;
deactivate;
exit $res;
";

/** Initialize project directory structure for specified project config.
    This function will create all needed directories for project.

    Params:
        config = Project configuration to initialize directory structure.
 **/
void initializeProjectDirs(in ProjectConfig config) {
    config.root_dir.mkdir(true);
    config.bin_dir.mkdir(true);
    config.conf_dir.mkdir(true);
    config.log_dir.mkdir(true);
    config.downloads_dir.mkdir(true);
    config.addons_dir.mkdir(true);
    config.data_dir.mkdir(true);
    config.backups_dir.mkdir(true);
    config.repositories_dir.mkdir(true);
}


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


void installVirtualenv(in ProjectConfig config) {
    import std.parallelism: totalCPUs;

    writeln("Installing virtualenv...");

    // TODO: make the function to run any command with proper error handling
    runCmdE(["python3", "-m", "virtualenv", config.venv_dir.toString]);

    import std.file: getAttributes, setAttributes;
    import std.conv : octal;
    config.bin_dir.join("run-in-venv").writeFile(
        SCRIPT_RUN_IN_ENV.format(config.venv_dir.join("bin", "activate")));
    config.bin_dir.join("run-in-venv").setAttributes(octal!755);

    config.venv_dir.join("bin", "pip").runCmdE(["install", "nodeenv"]);

    config.venv_dir.join("bin", "nodeenv").runCmdE([
        "--python-virtualenv", "--clean-src",
        "--jobs", totalCPUs.to!string, "--node", config.node_version]); 

    config.bin_dir.join("run-in-venv").runCmdE(
        ["npm", "set", "user", "0"]);
    config.bin_dir.join("run-in-venv").runCmdE(
        ["npm", "set", "unsafe-perm", "true"]);
}


void installOdoo(in ProjectConfig config) {
    config.venv_dir.join("bin", "pip").runCmdE([
        "install", "phonenumbers", "python-slugify", "setuptools-odoo",
        "cffi", "jinja2", "python-magic", "Python-Chart"]);
    writeln("Installing odoo to %s".format(config.odoo_path));

    config.venv_dir.join("bin", "python").runCmdE(
        ["setup.py", "develop"],
        config.odoo_path);

}
