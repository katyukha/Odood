module odood.cli.commands.database;

private import std.logger;
private import std.stdio;
private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;
private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand, exitWithCode;
private import odood.lib.project: Project;
private import odood.lib.odoo.serie: OdooSerie;
private import odood.lib.odoo.lodoo: BackupFormat;
private import odood.lib.utils: generateRandomString;
private import odood.lib.addons.addon: OdooAddon;

// TODO: Use specific exception tree for CLI part
private import odood.lib.exception: OdoodException;


class CommandDatabaseList: OdoodCommand {
    this() {
        this("list");
    }

    this(in string name) {
        super(name, "Show the databases available for this odoo instance.");
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        foreach(db; project.lodoo.databaseList()) {
            writeln(db);
        }
    }

}


class CommandDatabaseCreate: OdoodCommand {
    this() {
        super("create", "Create new odoo database.");
        this.add(new Flag("d", "demo", "Load demo data for this db"));
        this.add(new Flag(
            null, "recreate", "Recreate database if it already exists."));
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
        this.add(new Argument("name", "Name of database").required());
    }

    public override void execute(ProgramArgs args) {
        import std.array: empty;

        auto project = Project.loadProject;
        string dbname = args.arg("name");
        if (project.lodoo.databaseExists(dbname)) {
            if (args.flag("recreate")) {
                warningf(
                    "Dropting database %s before recreating it " ~
                    "(because --recreate option specified).", dbname);
                project.lodoo.databaseDrop(dbname);
            } else {
                throw new OdoodException(
                    "Database %s already exists!".format(dbname));
            }
        }
        project.lodoo.databaseCreate(
            dbname,
            args.flag("demo"),
            args.option("lang"),
            args.option("password"),
            args.option("country"));

        OdooAddon[] to_install;
        foreach(addon_name; args.options("install")) {
            auto addon = project.addons.getByName(addon_name);
            enforce!OdoodException(
                !addon.isNull,
                "Cannot find addon %s".format(addon));
            to_install ~= addon.get;
        }
        foreach(install_dir; args.options("install-dir")) {
            to_install ~= project.addons.scan(Path(install_dir));
        }

        if (!to_install.empty) {
            project.addons.install(dbname, to_install);
        }

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
            if (project.lodoo.databaseExists(dbname))
                project.lodoo.databaseDrop(dbname);
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
        bool db_exists = project.lodoo.databaseExists(args.arg("name"));
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
        project.lodoo.databaseRename(
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
        project.lodoo.databaseCopy(
            args.arg("old-name"), args.arg("new-name"));
    }
}


class CommandDatabaseBackup: OdoodCommand {
    this() {
        super("backup", "Backup database.");
        this.add(new Argument(
            "name", "Name of database to backup.").required());
        this.add(new Option(
            "d", "dest",
            "Destination path for backup. " ~
            "By default will store at project's backup directory."));
        this.add(new Flag(
            null, "zip", "Make ZIP backup with filestore."));
        this.add(new Flag(
            null, "sql", "Make SQL-only backup without filestore"));
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        auto b_format = BackupFormat.zip;
        if (args.flag("zip"))
            b_format = BackupFormat.zip;
        if (args.flag("sql"))
            b_format = BackupFormat.sql;

        //db_dump_file="$BACKUP_DIR/db-backup-$db_name-$(date -I).$(random_string 4)";
        immutable string tmpl_dest_name="db-backup-%s-%s.%s.%s";
        Path dest;
        if (args.option("dest")) {
            dest = Path(args.option("dest"));
            project.lodoo.databaseBackup(args.arg("name"), dest, b_format);
        } else {
            dest = project.lodoo.databaseBackup(args.arg("name"), b_format);
        }
    }
}


class CommandDatabaseRestore: OdoodCommand {
    this() {
        super("restore", "Restore database.");
        this.add(new Flag(
            null, "stun", "Stun database (disable cron and mail servers)"));
        this.add(new Flag(
            null, "selfish", "Stop the server while database being restored."));
        this.add(new Argument(
            "name", "Name of database to restore.").required());
        this.add(new Argument(
            "backup", "Path to backup to restore database from.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;
        auto backup_path = Path(args.arg("backup")).toAbsolute;
        enforce!OdoodException(
            backup_path.exists && backup_path.isFile,
            "Wrong backup path specified!");

        bool start_server = false;
        if (project.server.isRunning) {
            project.server.stop;
            start_server = true;
        }

        project.lodoo.databaseRestore(args.arg("name"), backup_path);

        // Optionally stun database
        if (args.flag("stun")) {
            auto db = project.dbSQL(args.arg("name"));
            scope(exit) db.close;
            db.stunDb();
        }

        if (start_server)
            project.server.spawn(true);
    }
}


class CommandDatabaseStun: OdoodCommand {
    this() {
        super("stun", "Stun database (disable cron and main servers).");
        this.add(new Argument(
            "name", "Name of database to stun.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto db = project.dbSQL(args.arg("name"));
        scope(exit) db.close;

        db.stunDb();
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
    }
}


