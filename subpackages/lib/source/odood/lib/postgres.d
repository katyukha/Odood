module odood.lib.postgres;

private import std.format: format;

private import odood.lib.exception: OdoodException;
private import odood.lib.theprocess;


void createNewPostgresUser(in string user, in string password) {
    // TODO: automatically create separate db user for odood
    //       that could be used to create other users for odoo instances.
    Process("sudo")
        .setArgs([
            "-u", "postgres", "-H",
            "--",
            "psql", "-c",
            "CREATE USER \"%s\" WITH CREATEDB PASSWORD '%s'".format(
                user, password),
        ])
        .execute()
        .ensureStatus();
}
