/// Module provides various odoo related routines
module odood.cli.commands.odoo;

private import std.logger;
private import std.exception: enforce;
private import std.typecons: Nullable;

private import darkcommand;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.project: Project;


class CommandOdooShell: OdoodCommand {
    Nullable!string db;

    this() {
        super("shell", "Run an interactive Odoo shell.");
        this.addOption!(db)("d", "db", "Database to run shell for.");
    }

    override int execute() {
        auto project = Project.loadProject;
        auto runner = project.server.getServerRunner("shell");
        runner.addArgs(project.odoo.serie > 10 ? "--no-http" : "--no-xmlrpc");
        if (!db.isNull)
            runner.addArgs("-d", db.get);
        runner.execv;
        return 0;
    }
}


class CommandOdooRecomputeField: OdoodCommand {
    string[] field;
    string[] db;
    bool allDb;
    string model;

    this() {
        super("recompute", "Recompute stored fields for a model.");
        this.addOption!(field)("f", "field", "Name of field to recompute.");
        this.addOption!(db)("d", "db", "Name of database to recompute fields for.");
        this.addFlag!(allDb)("", "all-db", "Recompute for all databases.");
        this.addOption!(model)("m", "model", "Name of model to recompute fields for");
    }

    override int execute() {
        auto project = Project.loadProject;
        string[] db_names = allDb ? project.databases.list() : db;
        enforce!OdoodCLIException(
            db_names.length > 0,
            "At least one database must be specified to recompute field");

        foreach(dbname; db_names) {
            infof("Recomputing fields: db=%s, model=%s, fields=%s", dbname, model, field);
            project.lodoo.recomputeField(dbname, model, field);
        }
        return 0;
    }
}


class CommandOdoo: OdoodCommand {
    this() {
        super("odoo", "Odoo-related utility commands.");
        this.add(new CommandOdooShell());
        this.add(new CommandOdooRecomputeField());
    }
}
