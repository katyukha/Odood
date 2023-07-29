module odood.cli.commands.psql;

private import std.logger;
private import std.format: format;
private import std.conv: to, ConvException;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import theprocess: Process;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;


class CommandPSQL: OdoodCommand {
    this() {
        super("psql", "Run psql for specified database");
        this.add(new Option(
            "d", "db", "Name of database to connect to.").required);
    }

    public override void execute(ProgramArgs args) {
        auto odoo_conf = Project.loadProject.getOdooConfig();

        auto psql = Process("psql")
            .withEnv("PGDATABASE", args.option("db"))
            .withEnv(
                "PGUSER",
                odoo_conf["options"].hasKey("db_user") ?
                    odoo_conf["options"].getKey("db_user") : "odoo")
            .withEnv(
                "PGPASSWORD",
                odoo_conf["options"].hasKey("db_password") ?
                    odoo_conf["options"].getKey("db_password") : "odoo");

        if (odoo_conf["options"].hasKey("db_host")) 
            psql.setEnv(
                "PGHOST", odoo_conf["options"].getKey("db_host"));
        if (odoo_conf["options"].hasKey("db_port")) {
            auto db_port = odoo_conf["options"].getKey("db_port");
            try {
                psql.setEnv("PGPORT", db_port.to!(int).to!string);
            } catch (ConvException) {
                warningf("Unparsable value for db port: %s", db_port);
            }
        }

        psql.execv;
    }
}

