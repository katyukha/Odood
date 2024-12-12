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

import odood.cli.utils: printLogRecord;


/// Create new database user in postgres db
void createDbUser(in string user, in string password) {
    import dpq.connection: Connection;

    auto connection_str = "host=%s port=%s dbname=postgres user=%s password=%s".format(
        environment.get("POSTGRES_HOST", "localhost"),
        environment.get("POSTGRES_PORT", "5432"),
        environment.get("POSTGRES_USER", "odoo"),
        environment.get("POSTGRES_PASSWORD", "odoo"));

    infof("Connecting to postgres via: %s", connection_str);
    auto connection = Connection(connection_str);
    scope(exit) connection.close();

    auto res_user_exists = connection.exec(
        "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='%s')".format(user));
    if (res_user_exists[0][0].as!string != "t") {
        infof("Creating db user '%s' with password '%s' for tests", user, password);
        connection.exec(
            "CREATE USER \"%s\" WITH CREATEDB PASSWORD '%s';".format(
                user, password));
    }
}

/// Generate db name for the test for specified project
string genDbName(in Project project, in string name) {
    return "odood%s-%s".format(project.odoo.serie.major, name);
}


/// Test server management functions
void testServerManagement(in Project project) {
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
void testDatabaseManagement(in Project project) {
    infof("Testing database management for %s", project);
    project.databases.list.empty.shouldBeTrue();

    project.databases.exists(project.genDbName("test-1")).shouldBeFalse();
    project.databases.create(project.genDbName("test-1"), true);
    project.databases.exists(project.genDbName("test-1")).shouldBeTrue();

    project.databases.exists(project.genDbName("test-2")).shouldBeFalse();
    project.databases.rename(project.genDbName("test-1"), project.genDbName("test-2"));
    project.databases.exists(project.genDbName("test-1")).shouldBeFalse();
    project.databases.exists(project.genDbName("test-2")).shouldBeTrue();

    project.databases.copy(project.genDbName("test-2"), project.genDbName("test-1"));
    project.databases.exists(project.genDbName("test-1")).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2")).shouldBeTrue();

    auto backup_path = project.databases.backup(project.genDbName("test-2"));

    project.databases.drop(project.genDbName("test-2"));
    project.databases.exists(project.genDbName("test-1")).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2")).shouldBeFalse();

    project.databases.restore(project.genDbName("test-2"), backup_path);
    project.databases.exists(project.genDbName("test-1")).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2")).shouldBeTrue();

    // Drop restored database and try to restore database by backup name
    project.databases.drop(project.genDbName("test-2"));
    project.databases.restore(project.genDbName("test-2"), backup_path.baseName);
    project.databases.exists(project.genDbName("test-1")).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2")).shouldBeTrue();

    // Drop databases
    project.databases.drop(project.genDbName("test-1"));
    project.databases.drop(project.genDbName("test-2"));
    project.databases.list.empty.shouldBeTrue();

    infof("Testing database management for %s. Complete: Ok.", project);
}


/// Test addons manager
void testAddonsManagementBasic(in Project project) {
    infof("Testing addons management for %s", project);
    project.databases.create(project.genDbName("test-1"), true);

    // Install/update/uninstall standard 'crm' addon
    project.addons.isInstalled(project.genDbName("test-1"), "crm").shouldBeFalse();
    project.addons.install(project.genDbName("test-1"), "crm");
    project.addons.isInstalled(project.genDbName("test-1"), "crm").shouldBeTrue();
    project.addons.update(project.genDbName("test-1"), "crm");
    project.addons.uninstall(project.genDbName("test-1"), "crm");
    project.addons.isInstalled(project.genDbName("test-1"), "crm").shouldBeFalse();

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
    project.addons.isInstalled(
            project.genDbName("test-1"), "generic_location").shouldBeFalse;
    project.addons.install(
            project.genDbName("test-1"), "generic_location");
    project.addons.isInstalled(
            project.genDbName("test-1"), "generic_location").shouldBeTrue;

    // Try to run tests for module generic_location
    auto test_result = project.testRunner()
        .addModule("generic_location")
        .useTemporaryDatabase()
        .registerLogHandler((in rec) { printLogRecord(rec); })
        .run();
    test_result.success.shouldBeTrue();

    // Try to fetch bureaucrate-knowledge from odoo apps
    project.addons.downloadFromOdooApps("bureaucrat_knowledge");
    project.directories.addons.join("bureaucrat_knowledge").exists.shouldBeTrue;
    project.directories.addons.join("bureaucrat_knowledge").isSymlink.shouldBeTrue;
    project.directories.addons.join("bureaucrat_knowledge").readLink.shouldEqual(
        project.directories.downloads.join("bureaucrat_knowledge"));

    // Test parsing addons-list.txt file
    auto parsed_addons = project.addons.parseAddonsList(
        Path("test-data", "addons-list.txt"));
    parsed_addons.length.should == 4;
    parsed_addons.canFind(project.addons.getByString("crm")).shouldBeTrue;
    parsed_addons.canFind(project.addons.getByString("sale")).shouldBeTrue;
    parsed_addons.canFind(project.addons.getByString("account")).shouldBeTrue;
    parsed_addons.canFind(project.addons.getByString("website")).shouldBeTrue;

    // Drop database
    project.databases.drop(project.genDbName("test-1"));
    infof("Testing addons management for %s. Complete: Ok.", project);
}


/// Test running scripts
void testRunningScripts(in Project project) {
    infof("Testing running scripts for %s", project);
    auto dbname = project.genDbName("test-1");
    project.databases.create(dbname, true);
    scope(exit) project.databases.drop(dbname);

    // Run SQL Script
    project.databases.get(dbname).runSQLScript(
        Path("test-data", "test-sql-script.sql"));

    // Check if data in database was updated
    with (project.databases.get(dbname)) {
        runSQLQuery(
            "SELECT name FROM res_partner WHERE id = 1"
        ).get(0, 0).as!string.get.shouldEqual("Test SQL 72");
        runSQLQuery(
            "SELECT name FROM res_partner WHERE id = 2"
        ).get(0, 0).as!string.get.shouldEqual("Test SQL 75");
    }

    // Run Python Script
    project.lodoo.runPyScript(
        dbname, Path("test-data", "test-py-script.py"));

    // Check if data in database was updated
    with (project.databases.get(dbname)) {
        runSQLQuery(
            "SELECT name FROM res_partner WHERE id = 1"
        ).get(0, 0).as!string.get.shouldEqual("Test PY 41");
        runSQLQuery(
            "SELECT name FROM res_partner WHERE id = 2"
        ).get(0, 0).as!string.get.shouldEqual("Test PY 42");
    }

    infof("Testing running scripts for %s. Complete: Ok.", project);
}


/// Run basic tests for project
void runBasicTests(in Project project) {
    /* Plan:
     * - test server management
     * - test database management
     * - test repo downloading
     * - test addons testing
     */

    // Test server management
    testServerManagement(project);

    // Test LOdoo Database operations
    testDatabaseManagement(project);

    // Test basic addons management
    testAddonsManagementBasic(project);

    // Test running scripts
    testRunningScripts(project);

    // TODO: Complete the test
}

@("Basic Test Odoo 18")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-18",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 17 instance
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
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(18));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    //project.runBasicTests;

    /*
     * TODO: Currently, because some addons used in tests are not ported to 17,
     *       we do not test addons management. But later, when that addons ported
     *       we have to chage this and run tests for addons management for Odoo 17
     */

    // Test server management
    testServerManagement(project);

    // Test LOdoo Database operations
    testDatabaseManagement(project);

    // Test basic addons management
    //testAddonsManagementBasic(project);

    // Test running scripts
    testRunningScripts(project);
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
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(17));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    //project.runBasicTests;

    /*
     * TODO: Currently, because some addons used in tests are not ported to 17,
     *       we do not test addons management. But later, when that addons ported
     *       we have to chage this and run tests for addons management for Odoo 17
     */

    // Test server management
    testServerManagement(project);

    // Test LOdoo Database operations
    testDatabaseManagement(project);

    // Test basic addons management
    //testAddonsManagementBasic(project);

    // Test running scripts
    testRunningScripts(project);
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
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(16));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests;
}


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
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(15));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests;
}


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
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(14));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests;
}


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
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(13));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests;
}


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
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(12));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Run basic tests
    project.runBasicTests;
}


@("Test resintall Odoo 14 to 15")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood-14-15",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 14 instance
    createDbUser("odood14to15test", "odoo");

    auto project = new Project(temp_path, OdooSerie(14));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odood14to15test",
            "odoo")
        .setHttp("localhost", "14169")
        .result();
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(14));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));


    // Test server management
    testServerManagement(project);

    // Test that server initialization works fine
    project.server.getServerRunner("--stop-after-init", "--no-http").execute;

    // Reinstall Odoo to version 15
    project.reinstallOdoo(OdooSerie(15), true);

    // Test project after Odoo reinstalled to version 15
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(15));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    // Test that server initialization works fine
    project.server.getServerRunner("--stop-after-init", "--no-http").execute;

    // Run basic tests
    project.runBasicTests;
}
