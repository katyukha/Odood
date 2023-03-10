module odood.lib.install.odoo;

private import std.logger;
private import std.format: format;
private import std.algorithm.searching: startsWith;
private import std.string: split, chomp;
private import std.exception: enforce;
private import std.conv: to;
private import std.regex;

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
        project.odoo.repo.chomp(".git"), project.odoo.branch);
    auto repo_name = project.odoo.repo.chomp(".git").split("/")[$-1];

    // TODO: Switch to tar.gz, for smaller archives
    if (!odoo_archive_path.exists) {
        infof(
            "Downloading odoo (%s) from %s to %s",
            project.odoo.branch, download_url, odoo_archive_path);
        download(download_url, odoo_archive_path);
    }

    // Extract, with unfloding content of odoo-<branch> to
    // dest folder directly.
    infof(
        "Extracting odoo from %s to %s",
        odoo_archive_path, project.odoo.path);
    extract_zip_archive(
        odoo_archive_path, project.odoo.path,
        "%s-%s/".format(repo_name, project.odoo.branch));
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

    if (project.odoo.serie < 8) {
        info("Installing odoo dependencies (specific for Odoo 7.0)");
        project.venv.installPyPackages(
            "vobject < 0.9.0",
            "psutil < 2",
            "reportlab <= 3.0",
            "Pillow < 4.0",
            "lxml < 4.0",
            "psycopg2 >= 2.2, < 2.8",
            "python-dateutil < 2",
            "babel",
            "docutils",
            "feedparser",
            "gdata",
            "Jinja2",
            "mako",
            "mock",
            "pydot",
            "python-ldap",
            "python-openid",
            "pytz",
            "pywebdav < 0.9.8",
            "pyyaml",
            "simplejson",
            "unittest2",
            "vatnumber",
            "Werkzeug<1",
            "xlwt",
        );
    } else {
        info("Installing odoo dependencies (requirements.txt)");
        project.venv.installPyRequirements(
            project.odoo.path.join("requirements.txt"));
    }

    infof("Installing odoo to %s", project.odoo.path);

    // Apply workarounds
    if (project.odoo.serie < 8) {
        auto setup_content = project.odoo.path.join("setup.py").readFileText()
            .replaceAll(regex("PIL", "g"), "Pillow")
            .replaceAll(regex("pychart"), "Python-Chart");
        project.odoo.path.join("setup.py").writeFile(setup_content);
    }

    project.venv.python(
        ["setup.py", "develop"],
        project.odoo.path);
}


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

    /* NOTE: We need to generate separate config for tests,
     *       because usualy, in case of running odoo normally, it have to print
     *       log to some log file, but in case of running tests, it is required
     *       to print logs to stderr or stdout, thus logs could be displayed
     *       to user and processed on the fly. Unfortunately, older versions of
     *       Odoo, do not support of passign empty value to '--logfile' option.
     *       Thus, the only way to write logs to file or stdout conditionally
     *       is to use separate config files for them.
     */

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
