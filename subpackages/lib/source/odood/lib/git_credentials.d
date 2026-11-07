/** Credentials for git repositories, from the `ODOOD_GIT_CREDENTIALS`
  * environment variable: one `<https URL prefix> <user>:<token>` per line.
  *
  * ```
  * https://github.com/my-org            x-access-token:<token>
  * https://gitlab.example.com/group/repo deploy-user:<token>
  * ```
  *
  * A line applies to the https repositories under its prefix, matched on
  * whole path segments, ignoring case and a trailing `.git`; the longest
  * matching prefix wins. They are kept in the environment rather than next
  * to the repository URLs, as those are committed, and an
  * `odoo_requirements.txt` belongs to the repository that lists the
  * dependency, not to the one being built.
  **/
module odood.lib.git_credentials;

private import std.algorithm.iteration: filter, splitter;
private import std.algorithm.searching: canFind, endsWith, findSplit, startsWith;
private import std.array: array, empty, split;
private import std.exception: enforce;
private import std.format: format;
private import std.process: environment;
private import std.string: splitLines, toLower;
private import std.typecons: Nullable;

private import odood.exception: OdoodException;
private import odood.git: GitURL, gitCredentialEnv;


/// Name of the environment variable holding the credentials.
immutable string GIT_CREDENTIALS_ENV = "ODOOD_GIT_CREDENTIALS";


/** Git env with the credentials that `ODOOD_GIT_CREDENTIALS` holds for
  * `url` (see `gitCredentialEnv`); empty when it holds none.
  **/
string[string] resolveGitCredentialEnv(in GitURL url) {
    auto credential = findGitCredential(
        parseGitCredentials(environment.get(GIT_CREDENTIALS_ENV, "")), url);
    if (credential.isNull)
        return null;
    return gitCredentialEnv(url, credential.get.user, credential.get.password);
}


private struct GitCredential {
    string host;    // see hostKey
    string[] path;  // see pathSegments
    string user;
    string password;
}

/// Lower-case `host[:port]`, without the default port 443.
private string hostKey(in string host_port) {
    auto result = host_port.toLower;
    return result.endsWith(":443") ? result[0 .. $ - 4] : result;
}

/// Lower-case segments of a URL path, without a trailing `.git`.
private string[] pathSegments(in string path) {
    auto segments = path.toLower.splitter('/').filter!(s => !s.empty).array;
    if (segments.length && segments[$ - 1].endsWith(".git"))
        segments[$ - 1] = segments[$ - 1][0 .. $ - 4];
    return segments;
}

private GitCredential[] parseGitCredentials(in string content) {
    GitCredential[] result;
    foreach(lineno, line; content.splitLines) {
        auto fields = line.split;
        if (fields.empty)
            continue;

        // Errors name the line only: it holds a token.
        immutable error = "Cannot parse %s, line %s: expected '<https URL prefix> <user>:<token>'."
            .format(GIT_CREDENTIALS_ENV, lineno + 1);
        enforce!OdoodException(
            fields.length == 2 && fields[0].startsWith("https://"), error);

        auto location = fields[0]["https://".length .. $].findSplit("/");
        auto credential = fields[1].split(":");
        enforce!OdoodException(
            !location[0].empty && !location[0].canFind("@") &&
                credential.length == 2 && !credential[0].empty && !credential[1].empty,
            error);

        result ~= GitCredential(
            hostKey(location[0]), pathSegments(location[2]), credential[0], credential[1]);
    }
    return result;
}

private Nullable!GitCredential findGitCredential(GitCredential[] credentials, in GitURL url) {
    Nullable!GitCredential result;
    if (url.scheme != "https")
        return result;

    immutable host = hostKey(url.port.length ? url.host ~ ":" ~ url.port : url.host);
    auto path = pathSegments(url.path);
    foreach(credential; credentials)
        if (credential.host == host && path.startsWith(credential.path) &&
                (result.isNull || credential.path.length > result.get.path.length))
            result = credential;
    return result;
}

unittest {
    import unit_threaded.assertions;

    auto credentials = parseGitCredentials(
        "https://github.com/my-org   x-access-token:org-token\n" ~
        "\n" ~
        "  https://github.com/my-org/special.git\tx-access-token:special-token  \n" ~
        "https://gitlab.example.com deploy:host-token\n" ~
        "https://git.example.com:443/team deploy:team-token\n");

    string tokenFor(in string url) {
        auto credential = findGitCredential(credentials, GitURL(url));
        return credential.isNull ? null : credential.get.password;
    }

    tokenFor("https://github.com/my-org/repo").shouldEqual("org-token");
    tokenFor("https://GitHub.com/My-Org/Repo.git").shouldEqual("org-token");
    // The longest prefix wins, whatever the order of the lines.
    tokenFor("https://github.com/my-org/special").shouldEqual("special-token");
    // Whole segments only.
    tokenFor("https://github.com/my-org-two/repo").shouldBeNull;
    tokenFor("https://github.com/my-org/special-two").shouldEqual("org-token");
    // A prefix without a path covers the host.
    tokenFor("https://gitlab.example.com/any/group/repo").shouldEqual("host-token");
    tokenFor("https://gitlab.example.com:8443/any/repo").shouldBeNull;
    // 443 is the https port, written or not.
    tokenFor("https://gitlab.example.com:443/any/repo").shouldEqual("host-token");
    tokenFor("https://git.example.com/team/repo").shouldEqual("team-token");
    // Not sent over ssh or http.
    tokenFor("git@github.com:my-org/repo.git").shouldBeNull;
    tokenFor("http://github.com/my-org/repo").shouldBeNull;
}

// Malformed lines are refused without echoing the token.
unittest {
    import std.algorithm: canFind;
    import unit_threaded.assertions;

    foreach(content; [
            "https://github.com/my-org secret-token",
            "https://github.com/my-org user:secret-token extra",
            "github.com/my-org user:secret-token",
            "https://user@github.com/my-org user:secret-token",
            "https://github.com/my-org :secret-token",
    ]) {
        auto e = parseGitCredentials("\n" ~ content).shouldThrow!OdoodException;
        e.msg.canFind("line 2").shouldBeTrue;
        e.msg.canFind("secret-token").shouldBeFalse;
    }
}
