module tests.basic;

import std.logger;
import std.file;
import std.process;
import std.array;
import std.format;
import std.algorithm;

import thepath;
import theprocess;
import unit_threaded.assertions;

import odood.lib.project;
import odood.utils.odoo.serie;
import odood.lib.odoo.config: OdooConfigBuilder;
import odood.git: GitURL;

import odood.cli.utils: printLogRecord;

import peque;


/// Prepare virtualenv options for test
auto getVenvOptions(in OdooSerie serie) {
    import odood.lib.venv: PyInstallType;
    import odood.lib.odoo.python: guessVenvOptions;

    auto venv_options = serie.guessVenvOptions;

    if (venv_options.install_type == PyInstallType.System)
        return venv_options;

    if (environment.get("ODOOD_PREFER_PY_INSTALL") == "build")
        venv_options.install_type = PyInstallType.Build;
    else if (environment.get("ODOOD_PREFER_PY_INSTALL") == "pyenv")
        venv_options.install_type = PyInstallType.PyEnv;

    return venv_options;
}

/// Create new database user in postgres db
void createDbUser(in string user, in string password) {

    string[string] connection_params = [
        "host": environment.get("POSTGRES_HOST", "localhost"),
        "port": environment.get("POSTGRES_PORT", "5432"),
        "user": environment.get("POSTGRES_USER", "odoo"),
        "password": environment.get("POSTGRES_PASSWORD", "odoo"),
        "dbname": "postgres",
    ];
    infof("Connecting to postgres via: %s", connection_params);
    auto connection = Connection(connection_params);

    auto res_user_exists = connection.exec(
        "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='%s')".format(user));
    if (res_user_exists[0][0].get!string != "t") {
        infof("Creating db user '%s' with password '%s' for tests", user, password);
        connection.exec(
            "CREATE USER \"%s\" WITH CREATEDB PASSWORD '%s';".format(
                user, password));
    }
}

/// Generate db name for the test for specified project
string genDbName(in Project project, in string name, in string ukey="n") {
    string ci_run_id = environment.get("GITHUB_RUN_ID", "1");
    return "odood%s-r%s-u%s-%s".format(project.odoo.serie.major, ci_run_id, ukey, name);
}


/// Test server management functions
void testServerManagement(in Project project, in string ukey="n") {
    infof("Testing server management for %s", project);
    import core.thread.osthread;
    import core.time;

    project.server.isRunning.should == false;

    project.server.start(15.seconds);

    // We have to wait while odoo starts
    Thread.sleep(3.seconds);

    project.server.isRunning.should == true;

    project.server.stop();

    // We have to wait while odoo stops
    Thread.sleep(2.seconds);

    project.server.isRunning.should == false;
    infof("Testing server management for %s. Complete: Ok.", project);
}


/// Test database management functions
void testDatabaseManagement(in Project project, in string ukey="n") {
    infof("Testing database management for %s", project);
    project.databases.list.empty.shouldBeTrue();

    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeFalse();
    project.databases.create(project.genDbName("test-1", ukey), true);
    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeTrue();

    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeFalse();
    project.databases.rename(project.genDbName("test-1", ukey), project.genDbName("test-2", ukey));
    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeFalse();
    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeTrue();

    project.databases.copy(project.genDbName("test-2", ukey), project.genDbName("test-1", ukey));
    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeTrue();

    auto backup_path = project.databases.backup(project.genDbName("test-2", ukey));

    project.databases.drop(project.genDbName("test-2", ukey));
    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeFalse();

    project.databases.restore(project.genDbName("test-2", ukey), backup_path);
    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeTrue();

    // Drop restored database and try to restore database by backup name
    project.databases.drop(project.genDbName("test-2", ukey));
    project.databases.restore(project.genDbName("test-2", ukey), backup_path.baseName);
    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeTrue();

    // Drop databases
    project.databases.drop(project.genDbName("test-1", ukey));
    project.databases.drop(project.genDbName("test-2", ukey));
    project.databases.list.empty.shouldBeTrue();

    infof("Testing database management for %s. Complete: Ok.", project);
}


/// Test addons manager
void testAddonsManagementBasic(in Project project, in string ukey="n") {
    infof("Testing addons management for %s", project);
    auto dbname = project.genDbName("test-a-1", ukey);
    project.databases.create(dbname, true);
    scope(exit) {
        // Remove test database
        project.databases.drop(dbname);

        // Remove clonned repositories to beable reuse this project for other tests
        foreach(p; project.directories.repositories.walk)
            p.remove();

        // Remove symlinks from custom_addons directory
        foreach(p; project.directories.addons.walk)
            p.remove;
    }

    // Install/update/uninstall standard 'crm' addon
    project.addons.isInstalled(dbname, "crm").shouldBeFalse();
    project.addons.install(dbname, "crm");
    project.addons.isInstalled(dbname, "crm").shouldBeTrue();
    project.addons.update(dbname, "crm");
    project.addons.uninstall(dbname, "crm");
    project.addons.isInstalled(dbname, "crm").shouldBeFalse();

    // Add repo 'generic-addons'
    project.addons.addRepo(
        "https://github.com/crnd-inc/generic-addons.git",
        false,  // single branch
        true,   // recursive
    );
    project.directories.repositories.join(
        "crnd-inc", "generic-addons", ".git").exists.shouldBeTrue;
    project.directories.addons.join("generic_location").exists.shouldBeTrue;
    project.directories.addons.join("generic_location").isSymlink.shouldBeTrue;
    project.directories.addons.join("generic_location").readLink.shouldEqual(
        project.directories.repositories.join(
            "crnd-inc", "generic-addons", "generic_location"));

    // Try to install generic_location module
    project.addons.isInstalled(dbname, "generic_location").shouldBeFalse;
    project.addons.install(dbname, "generic_location");
    project.addons.isInstalled(dbname, "generic_location").shouldBeTrue;

    // Try to run tests for module generic_location
    auto test_result = project.testRunner()
        .addModule("generic_location")
        .useTemporaryDatabase()
        .registerLogHandler((in rec) { printLogRecord(rec); })
        .run();
    test_result.success.shouldBeTrue();

    // Try to fetch web_responsive from odoo apps
    project.addons.downloadFromOdooApps("web_responsive");
    project.directories.addons.join("web_responsive").exists.shouldBeTrue;
    project.directories.addons.join("web_responsive").isSymlink.shouldBeTrue;
    project.directories.addons.join("web_responsive").readLink.shouldEqual(
        project.directories.downloads.join("web_responsive"));

    // Test parsing addons-list.txt file
    auto parsed_addons = project.addons.parseAddonsList(
        Path("test-data", "addons-list.txt"));
    parsed_addons.length.should == 4;
    parsed_addons.canFind(project.addons.getByString("crm")).shouldBeTrue;
    parsed_addons.canFind(project.addons.getByString("sale")).shouldBeTrue;
    parsed_addons.canFind(project.addons.getByString("account")).shouldBeTrue;
    parsed_addons.canFind(project.addons.getByString("website")).shouldBeTrue;

    infof("Testing addons management for %s. Complete: Ok.", project);
}


/// Test running scripts
void testRunningScripts(in Project project, in string ukey="n") {
    infof("Testing running scripts for %s", project);
    auto dbname = project.genDbName("test-1", ukey);
    project.databases.create(dbname, true);
    scope(exit) project.databases.drop(dbname);

    // Run SQL Script
    project.databases.get(dbname).runSQLScript(
        Path("test-data", "test-sql-script.sql"));

    // Check if data in database was updated
    with (project.databases.get(dbname)) {
        runSQLQuery(
            "SELECT name FROM res_partner WHERE id = 1"
        )[0][0].get!string.shouldEqual("Test SQL 72");
        runSQLQuery(
            "SELECT name FROM res_partner WHERE id = 2"
        )[0][0].get!string.shouldEqual("Test SQL 75");
    }

    // Run Python Script
    project.lodoo.runPyScript(
        dbname, Path("test-data", "test-py-script.py"));

    // Check if data in database was updated
    with (project.databases.get(dbname)) {
        runSQLQuery(
            "SELECT name FROM res_partner WHERE id = 1"
        )[0][0].get!string.shouldEqual("Test PY 41");
        runSQLQuery(
            "SELECT name FROM res_partner WHERE id = 2"
        )[0][0].get!string.shouldEqual("Test PY 42");
    }

    infof("Testing running scripts for %s. Complete: Ok.", project);
}

/** Test Assembly functionality
  *
  * Currently this is minimal test, to ensure basic mechanics just works (not fail)
  * In future tests have to be improved, maybe moved to separate file with detailed tests
  **/
void testAssembly(Project project, in string ukey="n") {
    infof("Testing running scripts for %s", project);

    scope(exit) {
        if (project.project_root.join("assembly").exists)
            project.project_root.join("assembly").remove();
    }

    project.assembly.isNull.shouldBeTrue;
    project.initializeAssembly;
    project.assembly.isNull.shouldBeFalse;

    auto assembly  = project.assembly.get;

    assembly.addSource(GitURL("https://github.com/crnd-inc/generic-addons"));
    assembly.addAddon("generic_mixin");
    assembly.save();

    assembly.dist_dir.join("generic_mixin").exists.shouldBeFalse;
    assembly.dist_dir.join("generic_tag").exists.shouldBeFalse;
    assembly.sync();
    assembly.dist_dir.join("generic_mixin").exists.shouldBeTrue;
    assembly.dist_dir.join("generic_tag").exists.shouldBeFalse;

    project.directories.addons.join("generic_mixin").exists.shouldBeFalse;
    project.directories.addons.join("generic_tag").exists.shouldBeFalse;
    assembly.link();
    project.directories.addons.join("generic_mixin").exists.shouldBeTrue;
    project.directories.addons.join("generic_mixin").isSymlink.shouldBeTrue;
    project.directories.addons.join("generic_mixin").readLink == assembly.dist_dir.join("generic_mixin");
    project.directories.addons.join("generic_tag").exists.shouldBeFalse;

    assembly.addAddon("generic_tag");
    assembly.save();

    assembly.dist_dir.join("generic_mixin").exists.shouldBeTrue;
    assembly.dist_dir.join("generic_tag").exists.shouldBeFalse;
    assembly.sync();
    assembly.dist_dir.join("generic_mixin").exists.shouldBeTrue;
    assembly.dist_dir.join("generic_tag").exists.shouldBeTrue;

    project.directories.addons.join("generic_mixin").exists.shouldBeTrue;
    project.directories.addons.join("generic_tag").exists.shouldBeFalse;
    assembly.link();
    project.directories.addons.join("generic_mixin").exists.shouldBeTrue;
    project.directories.addons.join("generic_mixin").isSymlink.shouldBeTrue;
    project.directories.addons.join("generic_mixin").readLink == assembly.dist_dir.join("generic_mixin");
    project.directories.addons.join("generic_tag").exists.shouldBeTrue;
    project.directories.addons.join("generic_tag").isSymlink.shouldBeTrue;
    project.directories.addons.join("generic_tag").readLink == assembly.dist_dir.join("generic_tag");

    infof("Testing running scripts for %s. Complete: Ok.", project);
}


/** Run basic tests for project
  *
  * Params:
  *    project = project to run tests for
  *    ukey = optional unique key to be used to split naming during parallel run
  **/
void runBasicTests(Project project, in string ukey="n") {
    /* Plan:
     * - test server management
     * - test database management
     * - test repo downloading
     * - test addons testing
     */

    // Test server management
    testServerManagement(project, ukey);

    // Test LOdoo Database operations
    testDatabaseManagement(project, ukey);

    // Test basic addons management
    testAddonsManagementBasic(project, ukey);

    // Test running scripts
    testRunningScripts(project, ukey);

    // Test assemblies
    testAssembly(project, ukey);

    // TODO: Complete the test
}

version(OSX) {}  // Do not run this test on macos yet
else @("Basic Test Odoo 19")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-19",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 19 instance
    createDbUser("odood19test", "odoo");

    auto project = new Project(temp_path, OdooSerie(19));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood19test",
            "odoo")
        .setHttp("localhost", "19069")
        .result();
    project.initialize(odoo_conf, project.odoo.serie.getVenvOptions);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(19));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    //project.runBasicTests("o19");

    /*
     * TODO: Currently, because some addons used in tests are not ported to 19,
     *       we do not test addons management. But later, when that addons ported
     *       we have to chage this and run tests for addons management for Odoo 18
     */

    // Test server management
    testServerManagement(project, "o19");

    // Test LOdoo Database operations
    testDatabaseManagement(project, "o19");

    // Test basic addons management
    //testAddonsManagementBasic(project, "o19");

    // Test running scripts
    testRunningScripts(project, "o19");
}

@("Basic Test Odoo 18")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-18",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 18 instance
    createDbUser("odood18test", "odoo");

    auto project = new Project(temp_path, OdooSerie(18));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood18test",
            "odoo")
        .setHttp("localhost", "18069")
        .result();
    project.initialize(odoo_conf, project.odoo.serie.getVenvOptions);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(18));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests("o18");
}

@("Basic Test Odoo 17")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-17",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 17 instance
    createDbUser("odood17test", "odoo");

    auto project = new Project(temp_path, OdooSerie(17));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood17test",
            "odoo")
        .setHttp("localhost", "17069")
        .result();
    project.initialize(odoo_conf, project.odoo.serie.getVenvOptions);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(17));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests("o17");
}


@("Basic Test Odoo 16")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-16",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 16 instance
    createDbUser("odood16test", "odoo");

    auto project = new Project(temp_path, OdooSerie(16));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood16test",
            "odoo")
        .setHttp("localhost", "16069")
        .result();
    project.initialize(odoo_conf, project.odoo.serie.getVenvOptions);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(16));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests("o16");
}


version(x86_64)
@("Basic Test Odoo 15")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-15",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 15 instance
    createDbUser("odood15test", "odoo");

    auto project = new Project(temp_path, OdooSerie(15));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood15test",
            "odoo")
        .setHttp("localhost", "15069")
        .result();
    project.initialize(odoo_conf, project.odoo.serie.getVenvOptions);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(15));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests("o15");
}


version(x86_64)
@("Basic Test Odoo 14")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-14",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 14 instance
    createDbUser("odood14test", "odoo");

    auto project = new Project(temp_path, OdooSerie(14));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood14test",
            "odoo")
        .setHttp("localhost", "14069")
        .result();
    project.initialize(odoo_conf, project.odoo.serie.getVenvOptions);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(14));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests("o14");
}


version(x86_64)
@("Basic Test Odoo 13")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-13",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 14 instance
    createDbUser("odood13test", "odoo");

    auto project = new Project(temp_path, OdooSerie(13));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood13test",
            "odoo")
        .setHttp("localhost", "13069")
        .result();
    project.initialize(odoo_conf, project.odoo.serie.getVenvOptions);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(13));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests("o13");
}


version(x86_64)
@("Basic Test Odoo 12")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-12",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 14 instance
    createDbUser("odood12test", "odoo");

    auto project = new Project(temp_path, OdooSerie(12));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood12test",
            "odoo")
        .setHttp("localhost", "12069")
        .result();
    project.initialize(odoo_conf, project.odoo.serie.getVenvOptions);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(12));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests("o12");
}


@("Test resintall Odoo 16 to 17")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-16-17",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 16 instance
    createDbUser("odood16to17test", "odoo");

    auto project = new Project(temp_path, OdooSerie(16));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood16to17test",
            "odoo")
        .setHttp("localhost", "16169")
        .result();
    project.initialize(odoo_conf, project.odoo.serie.getVenvOptions);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(16));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));


    // Test server management
    testServerManagement(project);

    // Test that server initialization works fine
    project.server.getServerRunner("--stop-after-init", "--no-http").execute;

    // Reinstall Odoo to version 17
    project.reinstallOdoo(OdooSerie(17), true);

    // Test project after Odoo reinstalled to version 17
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(17));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Test that server initialization works fine
    project.server.getServerRunner("--stop-after-init", "--no-http").execute;

    // Run basic tests
    project.runBasicTests("reo16t17");
}


// Unittests for virtualenvs.
// Just test if it could build python with different configurations.
@("Test virtualenv initializaton")
unittest {
    import std.process;
    import thepath.utils: createTempPath;
    import unit_threaded.assertions;
    import odood.lib.venv;
    import odood.utils.versioned: Version;

    auto save_env = environment.toAA;
    scope(exit) {
        // Restore env on exit
        if ("ODOOD_CACHE_DIR" in save_env)
            environment["ODOOD_CACHE_DIR"] = save_env["ODOOD_CACHE_DIR"];
        else
            environment.remove("ODOOD_CACHE_DIR");
    }

    auto root = createTempPath;
    scope(exit) root.remove();

    // No cachedir. Just test that venv installed and works
    auto venv1 = VirtualEnv(root.join("venv1"), PySerie.py3);
    venv1.initializeVirtualEnv(VenvOptions(
        install_type: PyInstallType.Build,
        py_version: "3.10.16",
    ));
    venv1.py_version.shouldEqual(Version(3, 10, 16));

    // Enable cachedir
    environment["ODOOD_CACHE_DIR"] = root.join("cache").toString;
    root.join("cache").exists.shouldBeFalse;

    // Create venv 2
    auto venv2 = VirtualEnv(root.join("venv2"), PySerie.py3);
    venv2.initializeVirtualEnv(VenvOptions(
        install_type: PyInstallType.Build,
        py_version: "3.10.16",
    ));
    venv2.py_version.shouldEqual(Version(3, 10, 16));

    // Check that python 3.10.16 is placed in cache
    root.join("cache").join("python", "python-3.10.16.tar.xz").exists.shouldBeTrue;

    // Create third venv with same python version
    auto venv3 = VirtualEnv(root.join("venv3"), PySerie.py3);
    venv3.initializeVirtualEnv(VenvOptions(
        install_type: PyInstallType.Build,
        py_version: "3.10.16",
    ));
    venv3.py_version.shouldEqual(Version(3, 10, 16));
}
