module odood.cli.commands.database;

private import core.time;
private import std.logger;
private import std.stdio: writeln;
private import std.format: format;
private import std.exception: enforce;
private import std.algorithm.sorting: sort;
private import std.algorithm.iteration: uniq;
private import std.string: join, empty, isNumeric;
private import std.range: iota;
private import std.conv: to;
private import std.typecons: Nullable;

private import thepath: Path;
private import darkcommand;

private import odood.cli.core: OdoodCommand, exitWithCode, OdoodCLIException;
private import odood.lib.project: Project;
private import odood.lib.odoo.test: generateTestDbName;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.odoo.db: BackupFormat;
private import odood.utils: generateRandomString;
private import odood.utils.addons.addon: OdooAddon;


class CommandDatabaseList: OdoodCommand {
    this() {
        super("list", "Show the databases available for this odoo instance.");
    }

    override int execute() {
        auto project = Project.loadProject;
        foreach(db; project.databases.list())
            writeln(db);
        return 0;
    }
}


class CommandDatabaseCreate: OdoodCommand {
    bool demo;
    bool recreate;
    bool tdb;
    string lang = "en_US";
    Nullable!string password;
    Nullable!string country;
    string[] install;
    string[] installDir;
    string[] installFile;
    Nullable!string name;

    this() {
        super("create", "Create new odoo database.");
        this.addFlag!(demo)("d", "demo", "Load demo data for this db");
        this.addFlag!(recreate)("r", "recreate", "Recreate database if it already exists.");
        this.addFlag!(tdb)("", "tdb", "Automatically generate default name of test database");
        this.addOption!(lang)("l", "lang",
            "Language of database, specified as ISO code of language.")
            .defaultValue("en_US");
        this.addOption!(password)("", "password", "Admin password for this database.");
        this.addOption!(country)("", "country", "Country for this db.");
        this.addOption!(install)("i", "install", "Install module specified by name.");
        this.addOption!(installDir)("", "install-dir", "Install all modules from directory.")
            .acceptsDirectories();
        this.addOption!(installFile)("", "install-file",
            "Install all modules listed in specified file.")
            .acceptsFiles();
        this.addArgument!(name)("name", "Name of database");
    }

    string getDatabaseName(in Project project) {
        if (!name.isNull)
            return name.get;
        if (tdb)
            return generateTestDbName(project);
        throw new OdoodCLIException(
            "It is required to specify name of database or option --tdb.");
    }

    override int execute() {
        auto project = Project.loadProject;
        string dbname = getDatabaseName(project);

        OdooAddon[] to_install;
        foreach(addon_name; install) {
            auto addon = project.addons.getByName(addon_name);
            enforce!OdoodCLIException(
                !addon.isNull,
                "Cannot find addon %s".format(addon_name));
            to_install ~= addon.get;
        }
        foreach(dir; installDir)
            to_install ~= project.addons.scan(Path(dir));

        foreach(ifile; installFile)
            to_install ~= project.addons.parseAddonsList(Path(ifile));

        if (project.databases.exists(dbname)) {
            if (recreate) {
                warningf(
                    "Dropping database %s before recreating it " ~
                    "(because --recreate option specified).", dbname);
                project.databases.drop(dbname);
            } else {
                throw new OdoodCLIException(
                    "Database %s already exists!".format(dbname));
            }
        }

        project.databases.create(
            dbname,
            demo,
            lang,
            password.isNull ? null : password.get,
            country.isNull ? null : country.get);

        if (!to_install.empty)
            project.addons.install(dbname, to_install);
        return 0;
    }
}


class CommandDatabaseDrop: OdoodCommand {
    string[] name;

    this() {
        super("drop", "Drop the odoo database.");
        this.addArgument!(name)("name", "Name of database(s) to drop.");
    }

    override int execute() {
        auto project = Project.loadProject;
        foreach(dbname; name)
            if (project.databases.exists(dbname))
                project.databases.drop(dbname);
        return 0;
    }
}


class CommandDatabaseExists: OdoodCommand {
    bool quiet;
    string name;

    this() {
        super("exists", "Check if database exists.");
        this.addFlag!(quiet)("q", "quiet", "Suppress output, just return exit code");
        this.addArgument!(name)("name", "Name of database");
    }

    override int execute() {
        auto project = Project.loadProject;
        bool db_exists = project.databases.exists(name);
        if (db_exists) {
            if (!quiet)
                writeln("Database %s exists!".format(name));
            exitWithCode(0, "Database exists");
        } else {
            if (!quiet)
                writeln("Database %s does not exist!".format(name));
            exitWithCode(1, "Database does not exist");
        }
        return 0;
    }
}


class CommandDatabaseIsInitialized: OdoodCommand {
    bool quiet;
    string name;

    this() {
        super("is-initialized",
            "Check if database is initialized as an Odoo database.");
        this.addFlag!(quiet)("q", "quiet", "Suppress output, just return exit code.");
        this.addArgument!(name)("name", "Name of database.");
    }

    override int execute() {
        auto project = Project.loadProject;
        bool initialized = project.databases.isInitialized(name);
        if (initialized) {
            if (!quiet)
                writeln("Database %s is initialized.".format(name));
            exitWithCode(0, "Database is initialized");
        } else {
            if (!quiet)
                writeln("Database %s is not initialized.".format(name));
            exitWithCode(1, "Database is not initialized");
        }
        return 0;
    }
}


class CommandDatabaseRename: OdoodCommand {
    string oldName;
    string newName;

    this() {
        super("rename", "Rename database.");
        this.addArgument!(oldName)("old-name", "Name of original database.");
        this.addArgument!(newName)("new-name", "New name of database.");
    }

    override int execute() {
        auto project = Project.loadProject;
        project.databases.rename(oldName, newName);
        return 0;
    }
}


class CommandDatabaseCopy: OdoodCommand {
    string oldName;
    string newName;

    this() {
        super("copy", "Copy database.");
        this.addArgument!(oldName)("old-name", "Name of original database.");
        this.addArgument!(newName)("new-name", "New name of database.");
    }

    override int execute() {
        auto project = Project.loadProject;
        project.databases.copy(oldName, newName);
        return 0;
    }
}


class CommandDatabaseBackup: OdoodCommand {
    bool zip;
    bool sql;
    bool all;
    Nullable!string dest;
    string[] name;

    this() {
        super("backup", "Backup database.");
        this.addFlag!(zip)("", "zip", "Make ZIP backup with filestore.");
        this.addFlag!(sql)("", "sql", "Make SQL-only backup without filestore");
        this.addFlag!(all)("a", "all", "Backup all databases");
        this.addOption!(dest)("d", "dest",
            "Destination path for backup. " ~
            "By default will store at project's backup directory.");
        this.addArgument!(name)("name", "Name of database(s) to backup.")
            .defaultValue([]);
    }

    override int execute() {
        auto project = Project.loadProject;

        enforce!OdoodCLIException(
            all || name.length > 0,
            "It is required to specify name of database to backup or option -a or --all!");

        auto b_format = BackupFormat.zip;
        if (zip)
            b_format = BackupFormat.zip;
        if (sql)
            b_format = BackupFormat.sql;

        string[] dbnames = all ? project.databases.list : name;

        if (!dest.isNull) {
            auto dest_path = Path(dest.get);
            enforce!OdoodCLIException(
                dbnames.length <= 1 || (dest_path.exists && dest_path.isDir),
                "If --dest option specified and it is not directory, then only one database allowed to backup at time!");
        }

        foreach(db; dbnames)
            if (!dest.isNull)
                project.databases.backup(db, Path(dest.get), b_format);
            else
                project.databases.backup(db, b_format);
        return 0;
    }
}


class CommandDatabaseRestore: OdoodCommand {
    bool stun;
    bool selfish;
    bool force;
    bool recreate;
    string name;
    string backup;

    this() {
        super("restore", "Restore database.");
        this.addFlag!(stun)("", "stun", "Stun database (disable cron and mail servers)");
        this.addFlag!(selfish)("", "selfish", "Stop the server while database being restored.");
        this.addFlag!(force)("f", "force", "Enforce restore, even if backup is not valid.");
        this.addFlag!(recreate)("r", "recreate", "Recreate database if it already exists.");
        this.addArgument!(name)("name", "Name of database to restore.");
        this.addArgument!(backup)("backup",
            "Path to backup (or name of backup) to restore database from.");
    }

    override int execute() {
        auto project = Project.loadProject;

        bool start_server = false;
        if (project.server.isRunning) {
            project.server.stop;
            start_server = true;
        }

        if (project.databases.exists(name)) {
            if (recreate) {
                warningf(
                    "Dropping database %s before recreating it " ~
                    "(because --recreate option specified).", name);
                project.databases.drop(name);
            } else if (project.databases.isInitialized(name)) {
                throw new OdoodCLIException(
                    "Database %s already exists and is not empty!".format(name));
            }
        }

        project.databases.restore(
            name,
            backup,
            force ? false : true,  // validate strict
        );

        if (stun)
            project.dbSQL(name).stunDb;

        if (start_server)
            project.server.start;
        return 0;
    }
}


class CommandDatabaseStun: OdoodCommand {
    string name;

    this() {
        super("stun", "Stun (neutralize) database (disable cron and mail servers).");
        this.addArgument!(name)("name", "Name of database to stun.");
    }

    override int execute() {
        auto project = Project.loadProject;
        project.dbSQL(name).stunDb;
        return 0;
    }
}


class CommandDatabasePopulate: OdoodCommand {
    string dbname;
    string[] model;
    string size = "small";
    int repeat = 1;

    this() {
        super("populate", "Populate database with test data.");
        this.addOption!(dbname)("d", "dbname", "Name of database to populate.");
        this.addOption!(model)("m", "model",
            "Name of model to populate. Could be specified multiple times.");
        this.addOption!(size)("s", "size", "Population size")
            .defaultValue("small")
            .acceptsValues(["small", "medium", "large"]);
        this.addOption!(repeat)("", "repeat", "Repeat population N times.")
            .defaultValue(1)
            .validateEachWith((int v) => v > 0, "must be a positive number.");
    }

    override protected void validate() {
        enforce!OdoodCLIException(
            model.length > 0,
            "At least one --model must be specified.");
    }

    override int execute() {
        auto project = Project.loadProject;

        foreach(i; iota(repeat)) {
            infof("Populating database... (iteration #%s of %s)", i + 1, repeat);
            project.databases.populate(dbname, model, size);
        }
        return 0;
    }
}


class CommandDatabaseEnsureInitialized: OdoodCommand {
    bool waitPg;
    long waitPgTimeout = 60;
    bool demo;
    string lang = "en_US";
    string name;

    this() {
        super("ensure-initialized",
              "Ensure a database exists and is initialized as an Odoo database. " ~
              "Idempotent: safe to use in K8s init containers.");
        this.addFlag!(waitPg)("", "wait-pg",
            "Wait for PostgreSQL to be ready before proceeding.");
        this.addOption!(waitPgTimeout)("", "wait-pg-timeout",
            "Maximum time to wait for PostgreSQL in seconds.")
            .defaultValue(60L);
        this.addFlag!(demo)("d", "demo",
            "Load demo data (only on first initialization).");
        this.addOption!(lang)("l", "lang",
            "Language code, e.g. en_US (only on first initialization).")
            .defaultValue("en_US");
        this.addArgument!(name)("name", "Name of database.");
    }

    override int execute() {
        auto project = Project.loadProject;

        if (waitPg) {
            auto pg_timeout = waitPgTimeout.seconds;
            infof("Waiting for PostgreSQL...");
            enforce!OdoodCLIException(
                project.server.waitForPostgres(pg_timeout),
                "PostgreSQL did not become available within the timeout.");
            infof("PostgreSQL is ready.");
        }

        project.databases.ensureInitialized(name, demo, lang);
        return 0;
    }
}


class CommandDatabase: OdoodCommand {
    this() {
        super("db", "Database management commands");
        this.add(new CommandDatabaseList());
        this.add(new CommandDatabaseCreate());
        this.add(new CommandDatabaseEnsureInitialized());
        this.add(new CommandDatabaseDrop());
        this.add(new CommandDatabaseExists());
        this.add(new CommandDatabaseIsInitialized());
        this.add(new CommandDatabaseRename());
        this.add(new CommandDatabaseCopy());
        this.add(new CommandDatabaseBackup());
        this.add(new CommandDatabaseRestore());
        this.add(new CommandDatabaseStun());
        this.add(new CommandDatabasePopulate());
    }
}
