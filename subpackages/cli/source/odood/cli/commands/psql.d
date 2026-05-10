module odood.cli.commands.psql;

private import darkcommand;
private import theprocess: Process;

private import odood.cli.core: OdoodCommand;
private import odood.lib.project: Project;


class CommandPSQL: OdoodCommand {
    string db;

    this() {
        super("psql", "Run psql for specified database");
        this.addOption!(db)("d", "db", "Name of database to connect to.");
    }

    override int execute() {
        Project.loadProject.psql
            .withEnv("PGDATABASE", db)
            .execv;
        return 0;
    }
}
