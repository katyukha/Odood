module odood.lib.install.odoo;

private import std.logger;
private import std.format: format;
private import std.algorithm.searching: startsWith;
private import std.string: split, chomp;
private import std.exception: enforce;
private import std.conv: to;
private import std.regex;

private import dini: Ini;
private import zipper: Zipper;

private import odood.exception: OdoodException;
private import odood.lib.project: Project;
private import odood.utils.odoo.serie: OdooSerie;

private import odood.git;
private import odood.utils;
private import odood.utils.versioned: Version;


/** Download Odoo to odoo.path specified by project
  *
  * Params:
  *     project = Project to download Odoo to.
 **/
void installDownloadOdoo(in Project project) {
    auto odoo_cache_dir = getCacheDir("odoo");

    // Cleanup Odoo if we do not use cache
    bool cleanup_odoo = odoo_cache_dir.isNull;

    auto odoo_archive_path = odoo_cache_dir.get(
        project.directories.downloads).join(
            "odoo.%s.zip".format(project.odoo.branch));
    scope(exit) {
        // Automatically remove downloaded odoo archive on extraction
        // completed (if cache not used)
        if (cleanup_odoo && odoo_archive_path.exists)
            odoo_archive_path.remove();
    }

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
    Zipper(
        odoo_archive_path.toAbsolute
    ).extractTo(
        project.odoo.path,
        "%s-%s/".format(repo_name, project.odoo.branch),  // unfoldpath
    );
}

/** Clone Odoo from Git
  *
  * Params:
  *     project = Project to download Odoo to.
 **/
void installCloneGitOdoo(in Project project) {
    gitClone(
        parseGitURL(project.odoo.repo),
        project.odoo.path,
        project.odoo.branch,
        true,  // Single branch
    );
}


/** Install Odoo in virtual environment of specified project
  *
  * Params:
  *     project = Project to download Odoo to.
  **/
void installOdoo(in Project project) {
    // Install python dependecnies
    string[] py_packages = [
        "phonenumbers", "python-slugify", "setuptools-odoo",
        "cffi", "jinja2", "python-magic", "Python-Chart", "lodoo",
    ];

    // Add version-specific py packages
    if (project.odoo.serie >= 14)
        py_packages ~= "pdfminer.six";

    /* On Odoo 15, there are some warnings in the logs, that ask to install
     * flanker, but it seems to be unstable, buggy and with bad support for
     * newer versions of Python. Thus we will not install it automatically
     * by default.
     * One more point to avoid installation of flanker by default,
     * is that it requires redis server, that is not needed for most of
     * simple Odoo installations.
     */
    //if (project.odoo.serie >= 15)
        //py_packages ~= "flanker";

    // Install py packages
    project.venv.installPyPackages(py_packages);

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
        // Patch requirements txt for Odoo 17 and 18 for python 3.10
        if (project.odoo.serie >= 16 && project.venv.py_version >= Version(3, 10) && project.venv.py_version < Version(3, 11)) {
            info("Patching Odoo requirements.txt to avoid usage of gevent 21.8.0...");
            auto requirements_content = project.odoo.path.join("requirements.txt").readFileText()
                .replaceAll(
                    regex(r"gevent==21\.8\.0", "g"),
                    "gevent==21.12.0");
            project.odoo.path.join("requirements.txt").writeFile(requirements_content);
            warningf("requirements.txt:\n%s", project.odoo.path.join("requirements.txt").readFileText());
        }

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

    // Apply patch to fix chrome "forbidden" errors
    // See https://github.com/odoo/odoo/pull/114930
    // And https://github.com/odoo/odoo/pull/115782
    if (project.odoo.serie == 12) {
        infof("Applying automatic patch to be able to run tours with Chrome 111");
        auto common_content = project.odoo.path.join(
            "odoo", "tests", "common.py"
        ).readFileText().
            replaceAll(
                regex(r"^([\t ]+)(self\.ws = websocket\.create_connection\(self\.ws_url\))$", "gm"),
                "$1# Automatic Odood patch for ability to run tours in Chrome 111.\n" ~
                "$1# See: https://github.com/odoo/odoo/pull/114930\n" ~
                "$1# See: https://github.com/odoo/odoo/pull/115782\n" ~
                "$1# $2\n" ~
                "$1self.ws = websocket.create_connection(self.ws_url, suppress_origin=True)");
        project.odoo.path.join(
            "odoo", "tests", "common.py"
        ).writeFile(common_content);
    }

    if (project.venv.py_version < Version(3, 10))
        project.venv.python(
            ["setup.py", "develop"],
            project.odoo.path,  // workDir
        );
    else
        // For newer versions of python use pip to install Odoo,
        // because setup.py does not work anymore
        project.venv.pip("install", "--editable", project.odoo.path.toString);
}


/** Generate and save Odoo configuration to project
  *
  * Params:
  *     project = Project save odoo config to.
  *     odoo_config = Ini struture that represents desired odoo config
  **/
void installOdooConfig(in Project project, in Ini odoo_config) {
    import std.random: uniform;
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
     *       Odoo, do not support passign empty value to '--logfile' option.
     *       Thus, the only way to write logs to file or stdout conditionally
     *       is to use separate config files for them.
     */

    // Update test config with different xmlrpc/http port to avoid conflicts
    // with running odoo server
    if (project.odoo.serie < OdooSerie(11)) {
        odoo_test_conf["options"].setKey(
            "xmlrpc_port",
            "%s%s69".format(
                project.odoo.serie.major,
                uniform(2, 9)));
        odoo_test_conf["options"].setKey(
            "longpolling_port",
            "%s%s72".format(
                project.odoo.serie.major,
                uniform(2, 9)));
    } else if (project.odoo.serie < OdooSerie(16)) {
        odoo_test_conf["options"].setKey(
            "http_port",
            "%s%s69".format(
                project.odoo.serie.major,
                uniform(2, 9)));
        odoo_test_conf["options"].setKey(
            "longpolling_port",
            "%s%s72".format(
                project.odoo.serie.major,
                uniform(2, 9)));
    } else {
        odoo_test_conf["options"].setKey(
            "http_port",
            "%s%s69".format(
                project.odoo.serie.major,
                uniform(2, 9)));
        odoo_test_conf["options"].setKey(
            "gevent_port",
            "%s%s72".format(
                project.odoo.serie.major,
                uniform(2, 9)));
    }

    // Disable logfile for test config, to enforce log to
    // stdout/stderr for tests
    odoo_test_conf["options"].setKey("logfile", "False");

    // Save test odoo config
    odoo_test_conf.save(project.odoo.testconfigfile.toString);

}
