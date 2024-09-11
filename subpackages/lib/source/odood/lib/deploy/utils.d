module odood.lib.deploy.utils;

private import std.format: format;
private import std.exception: enforce, errnoEnforce;

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


void createPostgresUser(in string username, in string password) {
    Process("psql")
        .withUser("postgres")
        .withArgs(
            "psql", "-c",
            "CREATE USER \"%s\" WITH CREATEDB PASSWORD '%s'".format(
                username, password),
        )
        .execute()
        .ensureOk(true);
}

