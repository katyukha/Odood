module odood.cli.commands.database;

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
        auto project = new Project();
        foreach(db; project.lodoo.databaseList()) {
            writeln(db);
        }
    }

}


class CommandDatabaseCreate: OdoodCommand {
    this() {
        super("create", "Create new odoo database.");
        this.add(new Option(
            "l", "lang",
            "Language of database, specified as ISO code of language."
        ).defaultValue("en_US"));
        this.add(new Option(
            null, "password", "Admin password for this database."));
        this.add(new Option(
            null, "country", "Country for this db."));
        this.add(new Flag("d", "demo", "Load demo data for this db"));
        this.add(new Argument("name", "Name of database").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        project.lodoo.databaseCreate(
            args.arg("name"),
            args.flag("demo"),
            args.option("lang"),
            args.option("password"),
            args.option("country"));
    }
}

class CommandDatabaseDrop: OdoodCommand {
    this() {
        super("drop", "Drop the odoo database.");
        this.add(new Argument("name", "Name of database").required.repeating);
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
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
        auto project = new Project();
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
        auto project = new Project();
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
        auto project = new Project();
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
        auto project = new Project();
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
        } else {
            import std.datetime.systime: Clock;
            string dest_name="db-backup-%s-%s.%s.%s".format(
                args.arg("name"),
                "%s-%s-%s".format(
                    Clock.currTime.year,
                    Clock.currTime.month,
                    Clock.currTime.day),
                generateRandomString(4),
                b_format
            );
            dest = project.directories.backups.join(dest_name);
        }

        project.lodoo.databaseBackup(args.arg("name"), dest, b_format);
    }
}


class CommandDatabaseRestore: OdoodCommand {
    this() {
        super("restore", "Restore database.");
        this.add(new Argument(
            "name", "Name of database to restore.").required());
        this.add(new Argument(
            "backup", "Path to backup to restore database from.").required());
    }

    public override void execute(ProgramArgs args) {
        auto project = new Project();
        auto backup_path = Path(args.arg("backup")).toAbsolute;
        enforce!OdoodException(
            backup_path.exists && backup_path.isFile,
            "Wrong backup path specified!");
        project.lodoo.databaseRestore(args.arg("name"), backup_path);
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
    }
}


