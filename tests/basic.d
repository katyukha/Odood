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


@("Basic Test Odoo 15")
unittest {
    auto temp_path = createTempPath(
        environment.get("TEST_ODOO_TEMP", std.file.tempDir),
        "tmp-odood",
    );
    scope(exit) temp_path.remove();

    // Create database use for odoo 15 instance
    createDbUser("odoo15", "odoo");

    auto serie = OdooSerie(15);
    auto project = new Project(temp_path, serie);
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
    project.odoo.serie.shouldEqual(serie);
    project.config_path.shouldEqual(temp_path.join("odood.yml"));

    /* Plan:
     * - test server management
     * - test database management
     * - test repo downloading
     * - test addons testing
     */

    // Test LOdoo Database operations
    project.lodoo.databaseList().empty.shouldBeTrue();

    project.lodoo.databaseExists("odoo15-test-1").shouldBeFalse();
    project.lodoo.databaseCreate("odoo15-test-1", true);
    project.lodoo.databaseExists("odoo15-test-1").shouldBeTrue();

    project.lodoo.databaseExists("odoo15-test-2").shouldBeFalse();
    project.lodoo.databaseRename("odoo15-test-1", "odoo15-test-2");
    project.lodoo.databaseExists("odoo15-test-1").shouldBeFalse();
    project.lodoo.databaseExists("odoo15-test-2").shouldBeTrue();

    project.lodoo.databaseCopy("odoo15-test-2", "odoo15-test-1");
    project.lodoo.databaseExists("odoo15-test-1").shouldBeTrue();
    project.lodoo.databaseExists("odoo15-test-2").shouldBeTrue();

    auto backup_path = project.lodoo.databaseBackup("odoo15-test-2");

    project.lodoo.databaseDrop("odoo15-test-2");
    project.lodoo.databaseExists("odoo15-test-1").shouldBeTrue();
    project.lodoo.databaseExists("odoo15-test-2").shouldBeFalse();

    project.lodoo.databaseRestore("odoo15-test-2", backup_path);
    project.lodoo.databaseExists("odoo15-test-1").shouldBeTrue();
    project.lodoo.databaseExists("odoo15-test-2").shouldBeTrue();

    // Drop databases
    project.lodoo.databaseDrop("odoo15-test-1");
    project.lodoo.databaseDrop("odoo15-test-2");

    // Test addons installation
    project.lodoo.databaseCreate("odoo15-test-1", true);
    project.addons.isInstalled("odoo15-test-1", "crm").shouldBeFalse();
    project.addons.install("odoo15-test-1", "crm");
    project.addons.isInstalled("odoo15-test-1", "crm").shouldBeTrue();
    project.addons.update("odoo15-test-1", "crm");
    project.addons.uninstall("odoo15-test-1", "crm");
    project.addons.isInstalled("odoo15-test-1", "crm").shouldBeFalse();
    project.lodoo.databaseDrop("odoo15-test-1");


    // TODO: Complete the test

}
