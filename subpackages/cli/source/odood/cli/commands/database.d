module odood.cli.commands.database;

private import std.logger;
private import std.stdio: writeln;
private import std.format: format;
private import std.exception: enforce;
private import std.algorithm.sorting: sort;
private import std.algorithm.iteration: uniq;
private import std.string: join, empty, isNumeric;
private import std.range: iota;
private import std.conv: to;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs, acceptsValues, validateEachWith;

private import odood.cli.core: OdoodCommand, exitWithCode, OdoodCLIException;
private import odood.lib.project: Project;
private import odood.lib.odoo.test: generateTestDbName;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.odoo.db: BackupFormat;
private import odood.utils: generateRandomString;
private import odood.utils.addons.addon: OdooAddon;


class CommandDatabaseList: OdoodCommand {
    this() {
        this("list");
    }

    this(in string name) {
        super(name, "Show the databases available for this odoo instance.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        foreach(db; project.databases.list())
            writeln(db);
    }

}


class CommandDatabaseCreate: OdoodCommand {
    this() {
        super("create", "Create new odoo database.");
        this.add(new Flag("d", "demo", "Load demo data for this db"));
        this.add(new Flag(
            "r", "recreate", "Recreate database if it already exists."));
        this.add(new Flag(
            null, "tdb", "Automatically generate default name of test database"));
        this.add(new Option(
            "l", "lang",
            "Language of database, specified as ISO code of language."
        ).defaultValue("en_US"));
        this.add(new Option(
            null, "password", "Admin password for this database."));
        this.add(new Option(
            null, "country", "Country for this db."));
        this.add(new Option(
            "i", "install", "Install module specified by name.").repeating);
        this.add(new Option(
            null, "install-dir", "Install all modules from directory.")
                .repeating);
        this.add(new Option(
            null, "install-file",
            "Install all modules listed in specified file.").repeating);
        this.add(new Argument("name", "Name of database").optional);
    }

    string getDatabaseName(ProgramArgs args, in Project project) {
        if (args.arg("name"))
            return args.arg("name");
        if (args.flag("tdb"))
            return generateTestDbName(project);
        throw new OdoodCLIException("It is required to specify name of database or option --tdb.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        string dbname = getDatabaseName(args, project);

        OdooAddon[] to_install;
        foreach(addon_name; args.options("install")) {
            auto addon = project.addons.getByName(addon_name);
            enforce!OdoodCLIException(
                !addon.isNull,
                "Cannot find addon %s".format(addon_name));
            to_install ~= addon.get;
        }
        foreach(install_dir; args.options("install-dir"))
            to_install ~= project.addons.scan(Path(install_dir));

        foreach(install_file; args.options("install-file"))
            to_install ~= project.addons.parseAddonsList(Path(install_file));

        if (project.databases.exists(dbname)) {
            if (args.flag("recreate")) {
                warningf(
                    "Dropting database %s before recreating it " ~
                    "(because --recreate option specified).", dbname);
                project.databases.drop(dbname);
            } else {
                throw new OdoodCLIException(
                    "Database %s already exists!".format(dbname));
            }
        }

        project.databases.create(
            dbname,
            args.flag("demo"),
            args.option("lang"),
            args.option("password"),
            args.option("country"));

        if (!to_install.empty)
            project.addons.install(dbname, to_install);
    }
}

class CommandDatabaseDrop: OdoodCommand {
    this() {
        super("drop", "Drop the odoo database.");
        this.add(new Argument("name", "Name of database").required.repeating);
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        foreach(dbname; args.args("name"))
            if (project.databases.exists(dbname))
                project.databases.drop(dbname);
    }
}


class CommandDatabaseExists: OdoodCommand {
    this() {
        super("exists", "Check if database exists.");
        this.add(new Flag(
            "-q", "quiet", "Suppress output, just return exit code"));
        this.add(new Argument("name", "Name of database").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        bool db_exists = project.databases.exists(args.arg("name"));
        if (db_exists) {
            if (!args.flag("quiet"))
                writeln("Database %s exists!".format(args.arg("name")));
            exitWithCode(0, "Database exists");
        } else {
            if (!args.flag("quiet"))
                writeln("Database does not %s exists!".format(args.arg("name")));
            exitWithCode(1, "Database does not exists");
        }
    }
}


class CommandDatabaseRename: OdoodCommand {
    this() {
        super("rename", "Rename database.");
        this.add(new Argument(
            "old-name", "Name of original database.").required());
        this.add(new Argument(
            "new-name", "New name of database.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        project.databases.rename(
            args.arg("old-name"), args.arg("new-name"));
    }
}


class CommandDatabaseCopy: OdoodCommand {
    this() {
        super("copy", "Copy database.");
        this.add(new Argument(
            "old-name", "Name of original database.").required());
        this.add(new Argument(
            "new-name", "New name of database.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        project.databases.copy(
            args.arg("old-name"), args.arg("new-name"));
    }
}


class CommandDatabaseBackup: OdoodCommand {
    this() {
        super("backup", "Backup database.");
        this.add(new Flag(
            null, "zip", "Make ZIP backup with filestore."));
        this.add(new Flag(
            null, "sql", "Make SQL-only backup without filestore"));
        this.add(new Flag(
            "a", "all", "Backup all databases"));
        this.add(new Option(
            "d", "dest",
            "Destination path for backup. " ~
            "By default will store at project's backup directory."));
        this.add(new Argument(
            "name", "Name of database to backup.").optional.repeating);
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        enforce!OdoodCLIException(
            args.flag("all") || args.args("name").length > 0,
            "It is required to specify name of database to backup or option -a or --all!");

        auto b_format = BackupFormat.zip;
        if (args.flag("zip"))
            b_format = BackupFormat.zip;
        if (args.flag("sql"))
            b_format = BackupFormat.sql;

        string[] dbnames = args.flag("all") ?
            project.databases.list : args.args("name");

        if (!args.option("dest").empty) {
            auto dest = Path(args.option("dest"));
            enforce!OdoodCLIException(
                dbnames.length <= 1 || (dest.exists && dest.isDir),
                "If --dest option specified and it is not directory, then only one database allowed to backup at time!");
        }

        foreach(db; dbnames)
            if (args.option("dest"))
                project.databases.backup(
                    db, Path(args.option("dest")), b_format);
            else
                project.databases.backup(db, b_format);
    }
}


class CommandDatabaseRestore: OdoodCommand {
    this() {
        super("restore", "Restore database.");
        this.add(new Flag(
            null, "stun", "Stun database (disable cron and mail servers)"));
        this.add(new Flag(
            null, "selfish", "Stop the server while database being restored."));
        this.add(new Flag(
            "f", "force", "Enforce restore, even if backup is not valid."));
        this.add(new Flag(
            "r", "recreate", "Recreate database if it already exists."));
        this.add(new Argument(
            "name", "Name of database to restore.").required());
        this.add(new Argument(
            "backup", "Path to backup (or name of backup) to restore database from.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        const auto backup_path = args.arg("backup");
        const string dbname = args.arg("name");

        bool start_server = false;
        if (project.server.isRunning) {
            project.server.stop;
            start_server = true;
        }

        if (project.databases.exists(dbname)) {
            if (args.flag("recreate")) {
                warningf(
                    "Dropting database %s before recreating it " ~
                    "(because --recreate option specified).", dbname);
                project.databases.drop(dbname);
            } else {
                throw new OdoodCLIException(
                    "Database %s already exists!".format(dbname));
            }
        }

        project.databases.restore(
            dbname,
            backup_path,
            args.flag("force") ? false : true,  // validate strict
        );

        // Optionally stun database
        if (args.flag("stun"))
            project.dbSQL(args.arg("name")).stunDb;

        if (start_server)
            project.server.start;
    }
}


class CommandDatabaseStun: OdoodCommand {
    this() {
        super("stun", "Stun (neutralize) database (disable cron and main servers).");
        this.add(new Argument(
            "name", "Name of database to stun.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        project.dbSQL(args.arg("name")).stunDb;
    }
}


class CommandDatabasePopulate: OdoodCommand {
    this() {
        super("populate", "Populate database with test data.");
        this.add(new Option(
            "d", "dbname", "Name of database to populate.").required());
        this.add(new Option(
            "m", "model", "Name of model to populate. Could be specified multiple times.").required.repeating);
        this.add(new Option(
            "s", "size", "Population size"
            ).defaultValue("small").acceptsValues(["small", "medium", "large"]));
        this.add(
            new Option(
                null, "repeat", "Repeat population N times."
            )
            .defaultValue("1")
            .validateEachWith(opt => opt.isNumeric, "must be a number.")
        );
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        foreach(i; iota(args.option("repeat").to!int)) {
            infof("Population database... (iteration #%s of %s)", i, args.option("repeat"));
            project.databases.populate(
                args.option("dbname"),
                args.options("model"),
                args.option("size"));
        }
    }
}


class CommandDatabase: OdoodCommand {
    this() {
        super("db", "Database management commands");
        this.add(new CommandDatabaseList());
        this.add(new CommandDatabaseCreate());
        this.add(new CommandDatabaseDrop());
        this.add(new CommandDatabaseExists());
        this.add(new CommandDatabaseRename());
        this.add(new CommandDatabaseCopy());
        this.add(new CommandDatabaseBackup());
        this.add(new CommandDatabaseRestore());
        this.add(new CommandDatabaseStun());
        this.add(new CommandDatabasePopulate());
    }
}


