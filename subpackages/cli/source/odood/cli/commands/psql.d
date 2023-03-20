module odood.cli.commands.psql;

private import std.logger;
private import std.format: format;
private import std.conv: to, ConvException;

private import commandr: Argument, Option, Flag, ProgramArgs;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;


class CommandPSQL: OdoodCommand {
    this() {
        super("psql", "Run psql for specified database");
        this.add(new Option(
            "d", "db", "Name of database to connect to.").required);
    }

    public override void execute(ProgramArgs args) {
        import std.process;
        import std.algorithm;
        import std.array;
        auto project = Project.loadProject;

        string[string] env = environment.toAA;

        auto odoo_conf = project.getOdooConfig();

        env["PGDATABASE"] = args.option("db");

        if (odoo_conf["options"].hasKey("db_host")) 
            env["PGHOST"] = odoo_conf["options"].getKey("db_host");
        if (odoo_conf["options"].hasKey("db_port")) {
            auto db_port = odoo_conf["options"].getKey("db_port");
            try {
                env["PGPORT"] = db_port.to!(int).to!string;
            } catch (ConvException) {
                warningf("Unparsable value for db port: %s", db_port);
            }
        }

        env["PGUSER"] = odoo_conf["options"].hasKey("db_user") ?
            odoo_conf["options"].getKey("db_user") : "odoo";
        env["PGPASSWORD"] = odoo_conf["options"].hasKey("db_password") ?
            odoo_conf["options"].getKey("db_password") : "odoo";

        execvpe(
            "psql", ["psql"],
            env.byKeyValue.map!(
                (i) => "%s=%s".format(i.key, i.value)).array);
    }
}

