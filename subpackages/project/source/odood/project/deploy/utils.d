module odood.project.deploy.utils;

private import std.logger: infof, tracef, errorf;
private import std.format: format;
private import std.exception: enforce;
private import std.conv: to, text, ConvException;
private import std.string: strip;
private import std.typecons: Nullable;
private static import std.process;

private import core.sys.posix.unistd: geteuid, getegid;

private import theprocess: Process;
private import thepath: Path;


void createSystemUser(
        in Path home,
        in string name,
        in Nullable!uint uid = Nullable!uint.init,
        in Nullable!uint gid = Nullable!uint.init) {
    infof("Creating system user for Odoo named '%s'", name);

    if (!uid.isNull || !gid.isNull) {
        // A deterministic UID/GID was requested (container builds). adduser
        // cannot create a *new* group with a fixed GID in the same call, so
        // create the group first, then the user bound to it. The GID defaults
        // to the UID when only the UID is provided (common container convention).
        immutable uint group_id = gid.isNull ? uid.get : gid.get;
        Process("addgroup")
            .withArgs(
                "--system",
                "--gid", group_id.to!string,
                name)
            .execute()
            .ensureOk(true);

        auto user_proc = Process("adduser")
            .withArgs(
                "--system",
                "--no-create-home",
                "--home", home.toString,
                "--quiet",
                "--gid", group_id.to!string);
        if (!uid.isNull)
            user_proc.addArgs("--uid", uid.get.to!string);
        user_proc.addArgs(name);
        user_proc.execute().ensureOk(true);
        infof(
            "User '%s' created successfully (uid=%s, gid=%s)",
            name,
            uid.isNull ? "auto" : uid.get.to!string,
            group_id.to!string);
        return;
    }

    Process("adduser")
        .withArgs(
            "--system",
            "--no-create-home",
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
        .withArgs([
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
        .withArgs([
            "-c",
            i"CREATE USER \"$(username)\" WITH CREATEDB PASSWORD '$(password)'".text,
        ])
        .withUser(username: "postgres", userWorkDir: true)
        .execute
        .ensureOk(true);
    infof("Postgresql user '%s' for Odoo created successfully.", username);
}
