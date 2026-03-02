/// Database utility functions
module odood.lib.odoo.db_utils;

private import peque: Connection;

private import odood.lib.project: Project;
private import odood.lib.odoo.config: parseOdooDatabaseConfig;


/** Open a peque connection to a PostgreSQL database using the connection
  * parameters from Odoo's configuration file.
  *
  * Params:
  *     project = the Odoo project whose odoo.conf is read for DB params
  *     dbname  = name of the database to connect to (default: "postgres")
  *
  * Returns:
  *     An open peque Connection.
  **/
package(odood.lib) Connection openPgConnection(in Project project, in string dbname) {
    auto db_conf = project.parseOdooDatabaseConfig;
    string[string] params = ["dbname": dbname];
    if (db_conf.host)
        params["host"] = db_conf.host;
    if (db_conf.port)
        params["port"] = db_conf.port;
    if (db_conf.user)
        params["user"] = db_conf.user;
    if (db_conf.password)
        params["password"] = db_conf.password;
    if (db_conf.sslmode)
        params["sslmode"] = db_conf.sslmode;
    return Connection(params);
}
