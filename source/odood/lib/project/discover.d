module odood.lib.project.discover;

private import std.string: splitLines, strip;
private import std.algorithm: startsWith;
private import std.regex;
private import std.typecons: Nullable, nullable;
private import std.exception;
private import std.format: format;

private import thepath: Path;

private import odood.lib.project:
    ProjectConfigOdoo, ProjectConfigDirectories, Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.venv: VirtualEnv;
private import odood.lib.odoo.python: guessPySerie;
private import odood.lib.exception: OdoodException;


// TODO: Implement commands that could allow odood to dicscover configuration

private auto RE_CONF_LINE=ctRegex!(
    `^\s*(?P<name>[\w_]+)\s*=\s*(?P<val>[^\s;#]+).*$`, "m");


class OdoodDiscoverError : OdoodException {
    mixin basicExceptionCtors;
}

/** Parse odoo-helper.conf configuration file
  **/
auto parseOdooHelperScriptsConfig(in string config_content) {
    string[string] result;
    
    ProjectConfigOdoo project_odoo;
    ProjectConfigDirectories project_directories;
    Nullable!Path project_root;
    Nullable!Path project_venv_path;

    foreach(string line; config_content.splitLines) {
        if (line.strip.startsWith("#"))
            // It is a comment. Skip
            continue;

        auto c = line.strip.matchFirst(RE_CONF_LINE);
        if (c.empty)
            continue;

        switch(c["name"]) {
            case "PROJECT_ROOT_DIR":
                project_root = Path(c["val"]).nullable;
                break;
            case "ODOO_VERSION":
                project_odoo.serie = OdooSerie(c["val"]);
                break;
            case "ODOO_BRANCH":
                project_odoo.branch = c["val"];
                break;
            case "LOG_FILE":
                project_odoo.logfile = Path(c["val"]);
                break;
            case "ODOO_CONF_FILE":
                project_odoo.configfile = Path(c["val"]);
                break;
            case "ODOO_PATH":
                project_odoo.path = Path(c["val"]);
                break;
            case "ODOO_PID_FILE":
                project_odoo.pidfile = Path(c["val"]);
                break;
            case "ODOO_REPO":
                project_odoo.repo = c["val"];
                break;
            case "CONF_DIR":
                project_directories.conf = Path(c["val"]);
                break;
            case "LOG_DIR":
                project_directories.log = Path(c["val"]);
                break;
            case "DOWNLOADS_DIR":
                project_directories.downloads = Path(c["val"]);
                break;
            case "ADDONS_DIR":
                project_directories.addons = Path(c["val"]);
                break;
            case "DATA_DIR":
                project_directories.data = Path(c["val"]);
                break;
            case "BACKUP_DIR":
                project_directories.backups = Path(c["val"]);
                break;
            case "REPOSITORIES_DIR":
                project_directories.repositories = Path(c["val"]);
                break;
            case "VENV_DIR":
                project_venv_path = Path(c["val"]).nullable;
                break;

            default:
                // Nothing todo for unknown options
                continue;
        }

        result[c["name"]] = c["val"];
    }

    // Validate parsed odoo-helper config
    // TOOD: Do additional validation if all required parameters available;
    enforce!OdoodDiscoverError(
        !project_root.isNull,
        "Cannot parse odoo-helper config!");
    enforce!OdoodDiscoverError(
        !project_venv_path.isNull,
        "Cannot parse odoo-helper config!");

    return new Project(
        project_root.get,
        project_directories,
        project_odoo,
        VirtualEnv(
            project_venv_path.get,
            guessPySerie(project_odoo.serie)));
}

/// ditto
auto parseOdooHelperScriptsConfig(in Path config_path) {
    return parseOdooHelperScriptsConfig(config_path.readFileText());
}

/** Discover the odoo-helper project in specified path
  *
  * Params:
  *     path = path to start searching for config in.
  *         The search will through this dir and parent directories.
  **/
auto discoverOdooHelper(in Path path) {
    if (path.baseName == "odoo-helper.conf")
        return parseOdooHelperScriptsConfig(path);

    auto config_path = path.searchFileUp("odoo-helper.conf");
    enforce!OdoodDiscoverError(
        !config_path.isNull,
        "Cannot find odoo-helper.conf inside %s".format(path));
    return parseOdooHelperScriptsConfig(config_path.get);
}


/// Check standard formatting
unittest {
    import unit_threaded.assertions;

    auto project = parseOdooHelperScriptsConfig("
# Example odoo-helper project config
PROJECT_ROOT_DIR=/home/me/odoo-16;
PROJECT_CONFIG_VERSION=1;
ODOO_VERSION=16.0;
ODOO_BRANCH=16.0-dev;
CONF_DIR=/home/me/odoo-16/conf;
LOG_DIR=/home/me/odoo-16/logs;
LOG_FILE=/home/me/odoo-16/logs/odoo.log;
LIBS_DIR=/home/me/odoo-16/libs;
DOWNLOADS_DIR=/home/me/odoo-16/downloads;
ADDONS_DIR=/home/me/odoo-16/custom_addons;
DATA_DIR=/home/me/odoo-16/data;
BIN_DIR=/home/me/odoo-16/bin;
VENV_DIR=/home/me/odoo-16/venv;
ODOO_PATH=/home/me/odoo-16/odoo;
ODOO_CONF_FILE=/home/me/odoo-16/conf/odoo.conf;
ODOO_TEST_CONF_FILE=/home/me/odoo-16/conf/odoo.test.conf;
ODOO_PID_FILE=/home/me/odoo-16/odoo.pid;
BACKUP_DIR=/home/me/odoo-16/backups;
REPOSITORIES_DIR=/home/me/odoo-16/repositories;
ODOO_REPO=https://github.com/odoo/odoo.git;
USE_UNBUFFER=1
");

    project.project_root.shouldEqual(Path("/home/me/odoo-16"));

    project.odoo.configfile.shouldEqual(Path("/home/me/odoo-16/conf/odoo.conf"));
    project.odoo.logfile.shouldEqual(Path("/home/me/odoo-16/logs/odoo.log"));
    project.odoo.path.shouldEqual(Path("/home/me/odoo-16/odoo"));
    project.odoo.pidfile.shouldEqual(Path("/home/me/odoo-16/odoo.pid"));
    project.odoo.serie.shouldEqual(OdooSerie("16.0"));
    project.odoo.branch.shouldEqual("16.0-dev");
    project.odoo.repo.shouldEqual("https://github.com/odoo/odoo.git");

    project.directories.conf.shouldEqual(Path("/home/me/odoo-16/conf"));
    project.directories.log.shouldEqual(Path("/home/me/odoo-16/logs"));
    project.directories.downloads.shouldEqual(Path("/home/me/odoo-16/downloads"));
    project.directories.addons.shouldEqual(Path("/home/me/odoo-16/custom_addons"));
    project.directories.data.shouldEqual(Path("/home/me/odoo-16/data"));
    project.directories.backups.shouldEqual(Path("/home/me/odoo-16/backups"));
    project.directories.repositories.shouldEqual(Path("/home/me/odoo-16/repositories"));

    project.venv.path.shouldEqual(Path("/home/me/odoo-16/venv"));
}

/// Check non-standard formatting
unittest {
    import unit_threaded.assertions;

    auto project = parseOdooHelperScriptsConfig("
# Example odoo-helper project config
PROJECT_ROOT_DIR=/home/me/odoo-16;
PROJECT_CONFIG_VERSION=1;  # Not used in Odood
ODOO_VERSION=16.0
ODOO_BRANCH=16.0-dev   # Some comment on branch
CONF_DIR=/home/me/odoo-16/conf;
    LOG_DIR=/home/me/odoo-16/logs;  # added spaces on start
LOG_FILE=/home/me/odoo-16/logs/odoo.log;
LIBS_DIR=/home/me/odoo-16/libs;
    DOWNLOADS_DIR=/home/me/odoo-16/downloads;
ADDONS_DIR=/home/me/odoo-16/custom_addons;
DATA_DIR=/home/me/odoo-16/data
BIN_DIR=/home/me/odoo-16/bin
    VENV_DIR=/home/me/odoo-16/venv
ODOO_PATH=/home/me/odoo-16/odoo;
ODOO_CONF_FILE=/home/me/odoo-16/conf/odoo.conf;
ODOO_TEST_CONF_FILE=/home/me/odoo-16/conf/odoo.test.conf;
ODOO_PID_FILE=/home/me/odoo-16/odoo.pid;
BACKUP_DIR=/home/me/odoo-16/backups;
REPOSITORIES_DIR=/home/me/odoo-16/repositories;
ODOO_REPO=https://github.com/odoo/odoo.git;
USE_UNBUFFER=1
");

    project.project_root.shouldEqual(Path("/home/me/odoo-16"));

    project.odoo.configfile.shouldEqual(Path("/home/me/odoo-16/conf/odoo.conf"));
    project.odoo.logfile.shouldEqual(Path("/home/me/odoo-16/logs/odoo.log"));
    project.odoo.path.shouldEqual(Path("/home/me/odoo-16/odoo"));
    project.odoo.pidfile.shouldEqual(Path("/home/me/odoo-16/odoo.pid"));
    project.odoo.serie.shouldEqual(OdooSerie("16.0"));
    project.odoo.branch.shouldEqual("16.0-dev");
    project.odoo.repo.shouldEqual("https://github.com/odoo/odoo.git");

    project.directories.conf.shouldEqual(Path("/home/me/odoo-16/conf"));
    project.directories.log.shouldEqual(Path("/home/me/odoo-16/logs"));
    project.directories.downloads.shouldEqual(Path("/home/me/odoo-16/downloads"));
    project.directories.addons.shouldEqual(Path("/home/me/odoo-16/custom_addons"));
    project.directories.data.shouldEqual(Path("/home/me/odoo-16/data"));
    project.directories.backups.shouldEqual(Path("/home/me/odoo-16/backups"));
    project.directories.repositories.shouldEqual(Path("/home/me/odoo-16/repositories"));

    project.venv.path.shouldEqual(Path("/home/me/odoo-16/venv"));
}

