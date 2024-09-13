module odood.lib.deploy.utils;

private import std.logger: infof;
private import std.format: format;
private import std.exception: enforce, errnoEnforce;
private import std.conv: to, text;

private import core.sys.posix.unistd: geteuid, getegid;
private import core.sys.posix.pwd: getpwnam_r, passwd;

private import theprocess: Process;
private import thepath: Path;


bool checkSystemUserExists(in string username) {
    import std.string: toStringz;
    passwd pwd;
    passwd* result;
    long bufsize = 16384;
    char[] buf = new char[bufsize];

    int s = getpwnam_r(username.toStringz, &pwd, &buf[0], bufsize, &result);
    errnoEnforce(
        s == 0,
        "Got error on attempt to check if user %s exists".format(username));
    if (result)
        return true;
    return false;
}


void createSystemUser(in Path home, in string name) {
    Process("adduser")
        .withArgs(
            "--system", "--no-create-home",
            "--home", home.toString,
            "--quiet",
            "--group",
            name)
        .execute()
        .ensureOk(true);
}


/** Check if PostgreSQL user with provided username exists
  **/
bool postgresCheckUserExists(in string username) {
    auto output = Process("psql")
        .setArgs([
            "-c",
            i"SELECT count(*) FROM pg_user WHERE usename = '$(username)';".text,
        ])
        .withUser("postgres")
        .execute
        .ensureOk(true)
        .output;

    return output.to!int == 0;
}


/** Create new PostgreSQL user for Odoo with provided credentials
  **/
void postgresCreateUser(in string username, in string password) {
    infof("Creating postgresql user '%s' for Odoo...", username);
    Process("psql")
        .setArgs([
            "-c",
            i"CREATE USER \"$(username)\" WITH CREATEDB PASSWORD '$(password)'".text,
        ])
        .withUser("postgres")
        .execute
        .ensureStatus(true);
    infof("Postgresql user '%s' for Odoo created successfully.", username);
}


/** Check if debian package is installed in system
  **/
bool dpkgCheckPackageInstalled(in string package_name) {
    auto result = Process("dpkg-query")
       .withArgs("--show", "--showformat='${db:Status-Status}'", package_name)
       .execute;
    if (result.isNotOk)
        return false;
    if (result.output == "installed")
        return true;
    return false;
}
