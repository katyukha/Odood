module odood.git.credential;

private import std.exception: enforce;
private import std.format: format;
private import std.conv: to, ConvException;
private import std.process: environment;
private import std.string: toLower;

private import odood.exception: OdoodException;
private import odood.git.url: GitURL;


/// Environment variable that passes the password to the credential helper.
package(odood) immutable string GIT_CREDENTIAL_PASSWORD_ENV = "ODOOD_GIT_CREDENTIAL_PASSWORD";


/** Environment for a git process that answers git's credential prompt for
  * the host of the https `url` with `user` and `password`.
  *
  * Neither ends up in a URL or on the command line, from where git stores or
  * echoes it: the password reaches the credential helper through an
  * environment variable. The config entries are added after those that
  * `GIT_CONFIG_COUNT` already sets in the environment, and replace the other
  * credential helpers for the host, so that a stored credential cannot
  * answer instead.
  *
  * The result goes on top of the process environment, as `withEnv` and the
  * `env` of `GitRepository` and `gitClone` apply it. Merged into another map
  * with its own `GIT_CONFIG_*` entries, the numbers collide.
  **/
string[string] gitCredentialEnv(in GitURL url, in string user, in string password) {
    enforce!OdoodException(
        url.scheme == "https",
        "Cannot use credentials for %s: only https URLs are supported.".format(url));

    uint count = 0;
    const existing = environment.get("GIT_CONFIG_COUNT", "");
    if (existing.length) {
        try count = existing.to!uint;
        catch (ConvException)
            throw new OdoodException(
                "Cannot add git credentials: GIT_CONFIG_COUNT is not a number: %s".format(
                    existing));
    }

    // Scoped to the host, so a redirect or submodule elsewhere gets nothing.
    immutable context = "credential.https://%s%s".format(
        url.host.toLower, url.port.length ? ":" ~ url.port : "");
    immutable string[2][] entries = [
        // An empty helper drops the ones configured before it.
        [context ~ ".helper", ""],
        [context ~ ".helper",
         `!f() { test "$1" = get && printf 'password=%%s\n' "$%s"; }; f`.format(
             GIT_CREDENTIAL_PASSWORD_ENV)],
        [context ~ ".username", user],
    ];

    string[string] result = [GIT_CREDENTIAL_PASSWORD_ENV: password];
    foreach(i, entry; entries) {
        result["GIT_CONFIG_KEY_%s".format(count + i)] = entry[0];
        result["GIT_CONFIG_VALUE_%s".format(count + i)] = entry[1];
    }
    result["GIT_CONFIG_COUNT"] = (count + entries.length).to!string;
    return result;
}

// Git answers with the given credentials for the url's host only, keeps the
// config entries already in the environment, and ignores other helpers.
unittest {
    import std.algorithm: canFind;
    import std.process: wait;
    import unit_threaded.assertions;
    import odood.git: gitProcess;

    // Run `git credential fill` for `host` the way git does before a fetch.
    string fill(in string[string] env, in string host) {
        auto pipes = gitProcess
            .withEnv(env)
            // Leave out the user's own git config and password prompts.
            .withEnv("GIT_CONFIG_GLOBAL", "/dev/null")
            .withEnv("GIT_CONFIG_NOSYSTEM", "1")
            .withEnv("GIT_TERMINAL_PROMPT", "0")
            .withEnv("GIT_ASKPASS", "")
            .withEnv("SSH_ASKPASS", "")
            .withArgs("credential", "fill")
            .pipe;
        pipes.stdin.write("protocol=https\nhost=%s\npath=owner/repo\n\n".format(host));
        pipes.stdin.close();
        string output;
        foreach(line; pipes.stdout.byLine)
            output ~= line.idup ~ "\n";
        pipes.pid.wait;
        return output;
    }

    // The environment already configures git: a helper that would answer
    // with a stale token, and an unrelated setting.
    immutable string[string] preset = [
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "credential.helper",
        "GIT_CONFIG_VALUE_0": `!f() { echo username=stale; echo password=stale; }; f`,
        "GIT_CONFIG_KEY_1": "user.name",
        "GIT_CONFIG_VALUE_1": "Preset User",
    ];
    auto saved = environment.toAA;
    foreach(key, value; preset)
        environment[key] = value;
    scope(exit) foreach(key; preset.keys) {
        if (auto old = key in saved)
            environment[key] = *old;
        else
            environment.remove(key);
    }

    auto env = gitCredentialEnv(
        GitURL("https://GitHub.com/owner/repo"), "x-access-token", "s3cret");

    auto output = fill(env, "github.com");
    output.canFind("username=x-access-token\n").shouldBeTrue;
    output.canFind("password=s3cret\n").shouldBeTrue;

    // Another host still sees only the preset helper.
    fill(env, "gitlab.com").canFind("s3cret").shouldBeFalse;

    // The preset entries still apply.
    gitProcess
        .withEnv(env)
        .withEnv("GIT_CONFIG_GLOBAL", "/dev/null")
        .withEnv("GIT_CONFIG_NOSYSTEM", "1")
        .withArgs("config", "user.name")
        .execute.ensureOk(true).output.shouldEqual("Preset User\n");

    gitCredentialEnv(GitURL("git@github.com:owner/repo"), "git", "s3cret")
        .shouldThrow!OdoodException;
}
