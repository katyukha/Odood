module odood.lib.deploy.utils;

private import std.logger: infof, tracef, errorf;
private import std.format: format;
private import std.exception: enforce, errnoEnforce;
private import std.conv: to, text, ConvException;
private import std.string: strip;
private static import std.process;

private import core.sys.posix.unistd: geteuid, getegid;
private import core.sys.posix.pwd: getpwnam_r, passwd;

private import theprocess: Process;
private import thepath: Path;


bool checkSystemUserExists(in string username) {
    import std.string: toStringz;
    import core.stdc.errno: ENOENT, ESRCH, EBADF, EPERM;
    passwd pwd;
    passwd* result;
    long bufsize = 16384;
    char[] buf = new char[bufsize];

    int s = getpwnam_r(username.toStringz, &pwd, &buf[0], bufsize, &result);
    if (s == ENOENT || s == ESRCH || s == EBADF || s == EPERM)
        // Such user does not exists
        return false;

    errnoEnforce(
        s == 0,
        "Got error on attempt to check if user %s exists".format(username));

    if (result)
        return true;

    return false;
}


void createSystemUser(in Path home, in string name) {
    infof("Creating system user for Odoo named '%s'", name);
    Process("adduser")
        .withArgs(
            "--system", "--no-create-home",
            "--home", home.toString,
            "--quiet",
            "--group",
            name)
        .execute()
        .ensureOk(true);
    infof("User '%s' created successfully", name);
}


/** Check if PostgreSQL user with provided username exists
  **/
bool postgresCheckUserExists(in string username) {
    // TODO: Use peque for this?
    auto output = Process("psql")
        .setArgs([
            "-t", "-A", "-c",
            i"SELECT count(*) FROM pg_user WHERE usename = '$(username)';".text,
        ])
        .withUser(username: "postgres", userWorkDir: true)
        .withFlag(std.process.Config.stderrPassThrough)
        .execute
        .ensureOk(true)
        .output.strip;

    bool result = false;
    try {
        result = output.to!int != 0;
    } catch (ConvException e) {
        errorf(
            "Cannot check if pg user '%s' already exists: cannot parse psql output.\n"~
            "Error: %s\n" ~
            "Psql output: %s\n" ~
            "Expected psql output is int: 1 if user exists 0 if no user exists.",
            username,
            e.toString,
            output);
        throw e;
    }

    return result;
}


/** Create new PostgreSQL user for Odoo with provided credentials
  **/
void postgresCreateUser(in string username, in string password) {
    // TODO: Use peque for this?
    infof("Creating postgresql user '%s' for Odoo...", username);
    Process("psql")
        .setArgs([
            "-c",
            i"CREATE USER \"$(username)\" WITH CREATEDB PASSWORD '$(password)'".text,
        ])
        .withUser(username: "postgres", userWorkDir: true)
        .execute
        .ensureOk(true);
    infof("Postgresql user '%s' for Odoo created successfully.", username);
}
