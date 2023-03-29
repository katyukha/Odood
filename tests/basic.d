module tests.basic;

import std.file;
import std.process;
import std.array;
import std.format;

import thepath;
import unit_threaded.assertions;

import odood.lib.project;
import odood.lib.odoo.serie;
import odood.lib.odoo.config: OdooConfigBuilder;


/// Create new database user in postgres db
void createDbUser(in string user, in string password) {
    import dpq.connection: Connection;
    auto connection = Connection(
        "host=%s port=%s dbname=postgres user=%s password=%s".format(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            environment.get("POSTGRES_USER", "odoo"),
            environment.get("POSTGRES_PASSWORD", "odoo"))
        );
    scope(exit) connection.close();
    connection.exec(
        "CREATE USER \"%s\" WITH CREATEDB PASSWORD '%s';".format(
            user, password));
}

/// Generate db name for the test for specified project
string genDbName(in Project project, in string name) {
    return "odood%s-%s".format(project.odoo.serie.major, name);
}


/// Test database management functions
void testDatabaseManagement(in Project project) {
    project.lodoo.databaseList().empty.shouldBeTrue();

    project.lodoo.databaseExists(project.genDbName("test-1")).shouldBeFalse();
    project.lodoo.databaseCreate(project.genDbName("test-1"), true);
    project.lodoo.databaseExists(project.genDbName("test-1")).shouldBeTrue();

    project.lodoo.databaseExists(project.genDbName("test-2")).shouldBeFalse();
    project.lodoo.databaseRename(project.genDbName("test-1"), project.genDbName("test-2"));
    project.lodoo.databaseExists(project.genDbName("test-1")).shouldBeFalse();
    project.lodoo.databaseExists(project.genDbName("test-2")).shouldBeTrue();

    project.lodoo.databaseCopy(project.genDbName("test-2"), project.genDbName("test-1"));
    project.lodoo.databaseExists(project.genDbName("test-1")).shouldBeTrue();
    project.lodoo.databaseExists(project.genDbName("test-2")).shouldBeTrue();

    auto backup_path = project.lodoo.databaseBackup(project.genDbName("test-2"));

    project.lodoo.databaseDrop(project.genDbName("test-2"));
    project.lodoo.databaseExists(project.genDbName("test-1")).shouldBeTrue();
    project.lodoo.databaseExists(project.genDbName("test-2")).shouldBeFalse();

    project.lodoo.databaseRestore(project.genDbName("test-2"), backup_path);
    project.lodoo.databaseExists(project.genDbName("test-1")).shouldBeTrue();
    project.lodoo.databaseExists(project.genDbName("test-2")).shouldBeTrue();

    // Drop databases
    project.lodoo.databaseDrop(project.genDbName("test-1"));
    project.lodoo.databaseDrop(project.genDbName("test-2"));
    project.lodoo.databaseList().empty.shouldBeTrue();
}


/// Test addons manager
void testAddonsManagementBasic(in Project project) {
    project.lodoo.databaseCreate(project.genDbName("test-1"), true);

    project.addons.isInstalled(project.genDbName("test-1"), "crm").shouldBeFalse();
    project.addons.install(project.genDbName("test-1"), "crm");
    project.addons.isInstalled(project.genDbName("test-1"), "crm").shouldBeTrue();
    project.addons.update(project.genDbName("test-1"), "crm");
    project.addons.uninstall(project.genDbName("test-1"), "crm");
    project.addons.isInstalled(project.genDbName("test-1"), "crm").shouldBeFalse();

    // Drop database
    project.lodoo.databaseDrop(project.genDbName("test-1"));
}

@("Basic Test Odoo 15")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 15 instance
    createDbUser("odoo15", "odoo");

    auto project = new Project(temp_path, OdooSerie(15));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odoo15",
            "odoo")
        .result();
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(15));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    /* Plan:
     * - test server management
     * - test database management
     * - test repo downloading
     * - test addons testing
     */

    // Test LOdoo Database operations
    testDatabaseManagement(project);

    // Test basic addons management
    testAddonsManagementBasic(project);

    // TODO: Complete the test
}


@("Basic Test Odoo 14")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 14 instance
    createDbUser("odoo14", "odoo");

    auto project = new Project(temp_path, OdooSerie(14));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odoo14",
            "odoo")
        .result();
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(14));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    /* Plan:
     * - test server management
     * - test database management
     * - test repo downloading
     * - test addons testing
     */

    // Test LOdoo Database operations
    testDatabaseManagement(project);

    // Test basic addons management
    testAddonsManagementBasic(project);

    // TODO: Complete the test
}

@("Basic Test Odoo 13")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 14 instance
    createDbUser("odoo13", "odoo");

    auto project = new Project(temp_path, OdooSerie(13));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odoo13",
            "odoo")
        .result();
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(13));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    /* Plan:
     * - test server management
     * - test database management
     * - test repo downloading
     * - test addons testing
     */

    // Test LOdoo Database operations
    testDatabaseManagement(project);

    // Test basic addons management
    testAddonsManagementBasic(project);

    // TODO: Complete the test
}


@("Basic Test Odoo 12")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 14 instance
    createDbUser("odoo12", "odoo");

    auto project = new Project(temp_path, OdooSerie(12));
    auto odoo_conf = OdooConfigBuilder(project)
        .setDBConfig(
            environment.get("POSTGRES_HOST", "localhost"),
            environment.get("POSTGRES_PORT", "5432"),
            "odoo12",
            "odoo")
        .result();
    project.initialize(odoo_conf);
    project.save();

    // Test created project
    project.project_root.shouldEqual(temp_path);
    project.odoo.serie.shouldEqual(OdooSerie(12));
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    /* Plan:
     * - test server management
     * - test database management
     * - test repo downloading
     * - test addons testing
     */

    // Test LOdoo Database operations
    testDatabaseManagement(project);

    // Test basic addons management
    testAddonsManagementBasic(project);

    // TODO: Complete the test
}
