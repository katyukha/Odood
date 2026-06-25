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
import odood.exception: OdoodException;


/// Prepare virtualenv options for test
auto getVenvOptions(in OdooSerie serie) {
    import odood.lib.python.venv: PyInstallType;
    import odood.lib.python.odoo: guessVenvOptions;

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

    // Capture row count for restore integrity check (#5)
    auto lang_count = project.databases.get(
        project.genDbName("test-2", ukey)
    ).runSQLQuery("SELECT COUNT(*) FROM res_lang")[0][0].get!string;

    auto backup_path = project.databases.backup(project.genDbName("test-2", ukey));

    // Test #1: Verify ZIP backup integrity — non-empty file, contains required entries
    (backup_path.getSize > 0).shouldBeTrue;
    {
        import darkarchive: DarkArchiveReader, DarkArchiveFormat;
        import odood.utils.odoo.db: parseDatabaseBackupManifest;

        parseDatabaseBackupManifest(backup_path);  // throws if manifest.json missing or unparseable

        auto reader = DarkArchiveReader!(DarkArchiveFormat.zip)(backup_path);
        auto e = reader.entries();
        bool hasDumpSql = false;
        foreach (i; 0 .. e.length)
            if (e[i].meta.pathname == "dump.sql") { hasDumpSql = true; break; }
        hasDumpSql.shouldBeTrue;
    }

    project.databases.drop(project.genDbName("test-2", ukey));
    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeFalse();

    project.databases.restore(project.genDbName("test-2", ukey), backup_path);
    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeTrue();

    // Test #5: Restore integrity — row count must match pre-backup value
    project.databases.get(
        project.genDbName("test-2", ukey)
    ).runSQLQuery("SELECT COUNT(*) FROM res_lang")[0][0].get!string.shouldEqual(lang_count);

    // Drop restored database and try to restore database by backup name
    project.databases.drop(project.genDbName("test-2", ukey));
    project.databases.restore(project.genDbName("test-2", ukey), backup_path.baseName);
    project.databases.exists(project.genDbName("test-1", ukey)).shouldBeTrue();
    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeTrue();

    // Test #2: SQL format backup/restore cycle
    {
        import odood.utils.odoo.db: BackupFormat;
        auto sql_backup = project.databases.backup(
            project.genDbName("test-2", ukey), BackupFormat.sql);
        scope(exit) if (sql_backup.exists) sql_backup.remove();

        sql_backup.exists.shouldBeTrue;
        (sql_backup.getSize > 0).shouldBeTrue;

        project.databases.drop(project.genDbName("test-2", ukey));
        project.databases.restore(project.genDbName("test-2", ukey), sql_backup);
        project.databases.isInitialized(project.genDbName("test-2", ukey)).shouldBeTrue;
        project.databases.get(
            project.genDbName("test-2", ukey)
        ).runSQLQuery("SELECT COUNT(*) FROM res_lang")[0][0].get!string.shouldEqual(lang_count);
    }

    // Test restore into pre-existing empty (uninitialized) DB — should succeed
    project.databases.drop(project.genDbName("test-2", ukey));
    {
        // Create a raw empty DB (no Odoo schema) by hand
        import odood.lib.odoo.db_utils: openPgConnection;
        auto conn = project.openPgConnection("postgres");
        conn.exec(
            "CREATE DATABASE \"%s\"".format(project.genDbName("test-2", ukey)));
    }
    project.databases.exists(project.genDbName("test-2", ukey)).shouldBeTrue();
    project.databases.isInitialized(project.genDbName("test-2", ukey)).shouldBeFalse();
    project.databases.restore(project.genDbName("test-2", ukey), backup_path);
    project.databases.isInitialized(project.genDbName("test-2", ukey)).shouldBeTrue();

    // Test restore into an initialized (non-empty) DB — should fail
    project.databases.restore(project.genDbName("test-2", ukey), backup_path).shouldThrow!OdoodException;

    // Test #4: getConfigDataDir reads from odoo.conf, not a hardcoded path
    {
        project.server.getConfigDataDir.shouldEqual(project.project_root.join("data"));

        auto alt_data_dir = project.project_root.join("data-alt");
        auto conf = project.server.getConfig;
        conf["options"].setKey("data_dir", alt_data_dir.toString);
        conf.save(project.odoo.configfile.toString);
        project.server.getConfigDataDir.shouldEqual(alt_data_dir);

        // Restore original
        conf["options"].setKey("data_dir", project.project_root.join("data").toString);
        conf.save(project.odoo.configfile.toString);
        project.server.getConfigDataDir.shouldEqual(project.project_root.join("data"));
    }

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
    project.directories.addons.join("generic_mixin").exists.shouldBeTrue;
    project.directories.addons.join("generic_mixin").isSymlink.shouldBeTrue;
    project.directories.addons.join("generic_mixin").readLink.shouldEqual(
        project.directories.repositories.join(
            "crnd-inc", "generic-addons", "generic_mixin"));

    // Try to install generic_mixin module
    project.addons.isInstalled(dbname, "generic_mixin").shouldBeFalse;
    project.addons.install(dbname, "generic_mixin");
    project.addons.isInstalled(dbname, "generic_mixin").shouldBeTrue;

    // Try to run tests for module generic_mixin and test_generic_mixin
    auto test_result = project.testRunner()
        .addModule("generic_mixin")
        .addModule("test_generic_mixin")
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

    // Run the sample 'generate_partners.py' script (documented in
    // docs/odood/src/custom-scripts.md). It creates N random res.partner
    // records, where N is read from the ODOOD_SCRIPT_PARTNER_COUNT environment
    // variable. This also checks that env-var parameters reach the script.
    auto countPartners() {
        return project.databases.get(dbname).runSQLQuery(
            "SELECT count(*) FROM res_partner")[0][0].get!long;
    }

    auto saved_count = environment.get("ODOOD_SCRIPT_PARTNER_COUNT", null);
    scope(exit) {
        if (saved_count is null)
            environment.remove("ODOOD_SCRIPT_PARTNER_COUNT");
        else
            environment["ODOOD_SCRIPT_PARTNER_COUNT"] = saved_count;
    }

    immutable partners_before = countPartners();
    environment["ODOOD_SCRIPT_PARTNER_COUNT"] = "7";
    project.lodoo.runPyScript(
        dbname, Path("test-data", "generate_partners.py"));
    (countPartners() - partners_before).shouldEqual(7);

    infof("Testing running scripts for %s. Complete: Ok.", project);
}

/** Test Assembly functionality
  *
  * Currently this is minimal test, to ensure basic mechanics just works (not fail)
  * In future tests have to be improved, maybe moved to separate file with detailed tests
  **/
void testAssembly(Project project, in string ukey="n") {
    infof("Testing assembly for %s", project);

    scope(exit) {
        if (project.project_root.join("assembly").exists)
            project.project_root.join("assembly").remove();
    }

    (project.assembly is null).shouldBeTrue;
    project.initializeAssembly;
    (project.assembly !is null).shouldBeTrue;

    auto assembly  = project.assembly;
    auto base_commit = assembly.repo.getCurrCommit;

    // Add generic_mixin to assembly
    assembly.addSource(GitURL("https://github.com/crnd-inc/generic-addons"));
    assembly.addAddon("generic_mixin");
    assembly.save();

    // Sync assembly and check that only generic_mixin addon added to assembly
    // (no changelog generated on sync)
    assembly.dist_dir.join("generic_mixin").exists.shouldBeFalse;
    assembly.dist_dir.join("generic_tag").exists.shouldBeFalse;
    assembly.changelog_path.exists.shouldBeFalse;
    assembly.changelog_latest_path.exists.shouldBeFalse;
    assembly.version_path.exists.shouldBeFalse;
    assembly.sync();
    assembly.dist_dir.join("generic_mixin").exists.shouldBeTrue;
    assembly.dist_dir.join("generic_tag").exists.shouldBeFalse;
    assembly.changelog_path.exists.shouldBeFalse;
    assembly.changelog_latest_path.exists.shouldBeFalse;
    assembly.version_path.exists.shouldBeFalse;

    // Generate changelog, end ensure that changelog was written
    assembly.generateChangelog(base_commit);
    assembly.changelog_path.exists.shouldBeTrue;
    assembly.changelog_latest_path.exists.shouldBeTrue;
    assembly.version_path.exists.shouldBeTrue;
    // Adding an addon is a MINOR (additive) bump, so 18.0.0.0.0 -> 18.0.0.1.0.
    assembly.version_path.readFileText.shouldEqual("%s.0.1.0\n".format(project.odoo.serie));

    // Link assembly and change that symlinks were created in custom_addons dir
    project.directories.addons.join("generic_mixin").exists.shouldBeFalse;
    project.directories.addons.join("generic_tag").exists.shouldBeFalse;
    assembly.link();
    project.directories.addons.join("generic_mixin").exists.shouldBeTrue;
    project.directories.addons.join("generic_mixin").isSymlink.shouldBeTrue;
    project.directories.addons.join("generic_mixin").readLink == assembly.dist_dir.join("generic_mixin");
    project.directories.addons.join("generic_tag").exists.shouldBeFalse;

    // Commit changes
    assembly.repo.add(assembly.spec_path);
    assembly.repo.commit("Added generic_tag");

    // Set new base for changelog generation
    base_commit = assembly.repo.getCurrCommit;

    // Add generic_tag addon
    assembly.addAddon("generic_tag");
    assembly.save();

    // Sync and check that addon added to assembly
    assembly.dist_dir.join("generic_mixin").exists.shouldBeTrue;
    assembly.dist_dir.join("generic_tag").exists.shouldBeFalse;
    assembly.sync();
    assembly.dist_dir.join("generic_mixin").exists.shouldBeTrue;
    assembly.dist_dir.join("generic_tag").exists.shouldBeTrue;

    // Generate (update) changelog and check that assembly version updated.
    assembly.generateChangelog(base_commit);
    // Another added addon -> another MINOR bump: 18.0.0.1.0 -> 18.0.0.2.0.
    assembly.version_path.readFileText.shouldEqual("%s.0.2.0\n".format(project.odoo.serie));

    // Link assembly and check that correct symlinks created
    project.directories.addons.join("generic_mixin").exists.shouldBeTrue;
    project.directories.addons.join("generic_tag").exists.shouldBeFalse;
    assembly.link();
    project.directories.addons.join("generic_mixin").exists.shouldBeTrue;
    project.directories.addons.join("generic_mixin").isSymlink.shouldBeTrue;
    project.directories.addons.join("generic_mixin").readLink == assembly.dist_dir.join("generic_mixin");
    project.directories.addons.join("generic_tag").exists.shouldBeTrue;
    project.directories.addons.join("generic_tag").isSymlink.shouldBeTrue;
    project.directories.addons.join("generic_tag").readLink == assembly.dist_dir.join("generic_tag");

    infof("Testing assembly for %s. Complete: Ok.", project);
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

@("Basic Test Odoo 19")
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
    import odood.lib.python.venv;
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
    root.join("cache").join("python", "python-3.10.16.tgz").exists.shouldBeTrue;

    // Create third venv with same python version
    auto venv3 = VirtualEnv(root.join("venv3"), PySerie.py3);
    venv3.initializeVirtualEnv(VenvOptions(
        install_type: PyInstallType.Build,
        py_version: "3.10.16",
    ));
    venv3.py_version.shouldEqual(Version(3, 10, 16));
}


@("Test script resolution precedence")
unittest {
    import thepath.utils: createTempPath;
    import unit_threaded.assertions;
    import std.typecons: Nullable, nullable;
    import odood.lib.odoo.script: resolveScriptPath;

    auto root = createTempPath;
    scope(exit) root.remove();

    // Path resolution does not need an installed Odoo, so a lightweight project
    // (test constructor) is enough.
    auto project = new Project(root.join("project"), OdooSerie(17));

    auto repo = root.join("repo");
    auto repo_scripts = repo.join(".odood-scripts");
    auto project_scripts = project.project_root.join("scripts");
    repo_scripts.mkdir(true);
    project_scripts.mkdir(true);

    // <repo>/.odood-scripts/ takes precedence over <project>/scripts/ when both
    // provide the script and a repo is in context.
    repo_scripts.join("shared.py").writeFile("repo");
    project_scripts.join("shared.py").writeFile("project");
    resolveScriptPath(project, "shared.py", repo.nullable)
        .readFileText.shouldEqual("repo");

    // <project>/scripts/ is used when the script is not in the repo dir.
    project_scripts.join("only_project.sql").writeFile("project");
    resolveScriptPath(project, "only_project.sql", repo.nullable)
        .readFileText.shouldEqual("project");

    // Without a repo in context, <repo>/.odood-scripts/ is not searched, so the
    // shared name resolves to <project>/scripts/ instead.
    resolveScriptPath(project, "shared.py", Nullable!Path.init)
        .readFileText.shouldEqual("project");

    // Absolute paths are used as is, regardless of the convention directories.
    auto abs_script = root.join("abs_script.py");
    abs_script.writeFile("abs");
    resolveScriptPath(project, abs_script.toString, repo.nullable)
        .readFileText.shouldEqual("abs");

    // A name that is nowhere on the search path fails.
    resolveScriptPath(project, "does_not_exist.py", repo.nullable)
        .shouldThrow!OdoodException;

    // A non-existent absolute path fails too.
    resolveScriptPath(project, root.join("missing.py").toString, repo.nullable)
        .shouldThrow!OdoodException;
}
