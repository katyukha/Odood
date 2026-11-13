module odood.git.url;

private import std.logger: infof;
private import std.regex: regex, matchFirst;
private import std.exception: enforce;
private import std.format: format;
private import std.process: environment;
private import std.string: startsWith, endsWith, toLower;
private import std.algorithm.iteration: splitter;

private import thepath: Path;

private import odood.exception: OdoodException;
private import theprocess: Process;

// TODO: Think about using https://code.dlang.org/packages/urld
// TODO: Add parsing of branch name from url
// TODO: Cleanup, split Odood and CRND logic away from this file,
//       thus making it more universal
/// Regex for parsing git URL
private auto RE_GIT_URL = regex(
    `^((?P<scheme>http|https|ssh|git)://)?((?P<user>[\w\-\+\.]+)(:(?P<password>[\w\-\.\+]+))?@)?(?P<host>[\w\-\.]+)(:(?P<port>\d+))?(/|:)((?P<path>[\w\-\/\.]+?)(?:\.git)?)$`);




/// Struct to handle git urls
struct GitURL {
    private string _scheme;
    private string _user;
    private string _password;
    private string _host;
    private string _port;
    private string _path;

    string scheme() const => _scheme;
    string user() const => _user;
    string password() const => _password;
    string host() const => _host;
    string port() const => _port;
    string path() const => _path;

    /// Whether this URL refers to a local repository (filesystem path or
    /// `file://` URL) rather than a remote host. All local targets are
    /// normalized to the `file` scheme on parse, so the scheme alone is the
    /// discriminator — loud and inspectable for anyone branching on it.
    bool isLocal() const => _scheme == "file";

    /** Check if the URL carries embedded credentials: a password, or the
      * user of an http(s) URL, which may be a token
      * (`https://<token>@github.com/...`). An ssh user (`git@host:...`)
      * only names the account to log in as.
      *
      * A URL with credentials leaks them by several routes — it is stored in
      * the clear in a clone's git config, may end up in serialized configs,
      * and is echoed back inside git's own error messages — so callers that
      * persist URLs should refuse such input and take credentials out-of-band
      * instead.
      **/
    bool hasCredentials() const => _password.length > 0 || userIsCredential;

    /// Whether the user is a credential (see `hasCredentials`).
    private bool userIsCredential() const =>
        _user.length > 0 && (_scheme == "https" || _scheme == "http");

    /** Name of the repository: the URL path after the host, with
      * surrounding slashes and a trailing `.git` stripped — e.g.
      * `owner/repo` for `https://host/owner/repo.git`. For a local
      * repository this is the filesystem path without the leading slash.
      * Case is preserved (unlike `normalizedKey`).
      **/
    string repoName() const {
        string p = _path;
        while (p.length && p[0] == '/')
            p = p[1 .. $];
        while (p.length && p[$ - 1] == '/')
            p = p[0 .. $ - 1];
        if (p.endsWith(".git"))
            p = p[0 .. $ - 4];
        return p;
    }

    /** Short name of the repository: the last segment of `repoName` —
      * e.g. `repo` for `https://host/owner/repo.git`.
      **/
    string repoShortName() const {
        auto p = repoName;
        foreach_reverse(i, c; p)
            if (c == '/')
                return p[i + 1 .. $];
        return p;
    }

    /// Test hasCredentials / repoName / repoShortName
    unittest {
        import unit_threaded.assertions;

        with (GitURL("https://github.com/katyukha/odood.git")) {
            hasCredentials.shouldBeFalse;
            repoName.shouldEqual("katyukha/odood");
            repoShortName.shouldEqual("odood");
        }

        // ssh 'git@' user is not a secret; scp-form path parses the same.
        with (GitURL("git@gitlab.crnd.pro:crnd-opensource/crnd-web.git")) {
            hasCredentials.shouldBeFalse;
            repoName.shouldEqual("crnd-opensource/crnd-web");
            repoShortName.shouldEqual("crnd-web");
        }

        // Embedded password is a credential.
        with (GitURL("https://user:token@github.com/owner/repo")) {
            hasCredentials.shouldBeTrue;
            repoName.shouldEqual("owner/repo");
        }

        // So is a user alone on http(s): it may be a token.
        GitURL("https://ghp_token@github.com/owner/repo").hasCredentials.shouldBeTrue;

        // Deep paths (e.g. gitlab subgroups) keep all segments in repoName.
        with (GitURL("https://gitlab.com/group/subgroup/repo.git")) {
            repoName.shouldEqual("group/subgroup/repo");
            repoShortName.shouldEqual("repo");
        }

        // Case is preserved (unlike normalizedKey).
        GitURL("https://github.com/OCA/Web").repoName.shouldEqual("OCA/Web");

        // Local URLs: the parser keeps '.git' in the path, the property
        // strips it; the leading slash is dropped.
        with (GitURL("file:///data/repos/myrepo.git")) {
            hasCredentials.shouldBeFalse;
            repoName.shouldEqual("data/repos/myrepo");
            repoShortName.shouldEqual("myrepo");
        }
        GitURL(Path("/tmp/some-repo")).repoShortName.shouldEqual("some-repo");
    }

    @disable this();

    /** Create a git URL that refers to a local repository.
      *
      * This is the only way to build a `GitURL` from a bare filesystem path —
      * the string constructor accepts local targets solely in explicit
      * `file://` form, so there is no guessing whether a string is a path or
      * a remote. The path must be absolute (relative paths are not supported:
      * they cannot be expressed as `file://` URLs and their meaning depends
      * on the current working directory).
      **/
    this(in Path path) {
        enforce!OdoodException(
            path.isAbsolute,
            "Cannot create git URL from relative path '%s'! Only absolute paths are supported.".format(path));
        _scheme = "file";
        _path = path.toString;
    }

    this(in string url) {
        // Local repositories are accepted only in explicit file:// form (or
        // via the Path constructor). Anything else that looks like a
        // filesystem path is rejected loudly rather than guessed at.
        if (url.startsWith("file://")) {
            auto p = url["file://".length .. $];
            enforce!OdoodException(
                p.startsWith("/"),
                "Cannot parse git url '%s': file:// URLs must contain an absolute path.".format(url));
            _scheme = "file";
            _path = p;
            return;
        }
        enforce!OdoodException(
            !url.startsWith("/") && !url.startsWith("./") && !url.startsWith("../"),
            ("Cannot parse git url '%s': it looks like a filesystem path. " ~
             "Use GitURL(Path) or an absolute file:// URL for local repositories.").format(url));

        auto re_match = url.matchFirst(RE_GIT_URL);
        enforce!OdoodException(
            !re_match.empty,
            "Cannot parse git url '%s'".format(url));

        _user = re_match["user"];
        _password = re_match["password"];
        _host = re_match["host"];
        _port = re_match["port"];
        _path = re_match["path"];

        // If no scheme detected, but there is user in the URL, then
        // it seems to be SSH url
        if (!re_match["scheme"] && user)
            // TODO: may be use separate regex for SSH urls
            _scheme = "ssh";
        else
            _scheme = re_match["scheme"];
    }

    /** Convert to string that is suitable to pass to git clone.
      *
      * Includes any embedded credentials (user/password). Use this only
      * where a clone-ready URL is required; for logging or display use
      * `toString`, which strips the user and the password.
      *
      * Params:
      *     no_credentials = leave out the credentials (see `hasCredentials`),
      *         for a URL that is persisted.
      **/
    string toUrl(in bool no_credentials = false) const {
        if (isLocal)
            return "file://" ~ _path;

        string res;
        if (scheme)
            res ~= "%s://".format(scheme);

        if (user.length && !(no_credentials && userIsCredential)) {
            res ~= user;
            if (password.length && !no_credentials)
                res ~= ":" ~ password;
            res ~= "@";
        }
        res ~= host;

        if (port) res ~= ":%s".format(port);

        res ~= "/" ~ path;
        return res;
    }

    /** Normalized identity key of the repository this URL points to.
      *
      * Different spellings of the same remote — https vs ssh (scp form),
      * with or without embedded credentials, trailing `.git` or a trailing
      * slash — all collapse to one key of the form `host/path`, case-folded.
      * Scheme, credentials, and port are ignored (the same repo is typically
      * reachable over several transports). Local repositories key by their
      * absolute path with case preserved (filesystem paths are
      * case-sensitive), normalized only for trailing slashes.
      *
      * Intended for identity comparison and dictionary keys (see `sameRepo`);
      * it is NOT a clonable URL.
      **/
    string normalizedKey() const {
        if (isLocal) {
            string p = _path;
            while (p.length > 1 && p[$ - 1] == '/')
                p = p[0 .. $ - 1];
            return p;
        }
        return (_host ~ "/" ~ repoName).toLower;
    }

    /** Check if this URL and `other` refer to the same repository,
      * comparing their normalized keys (see `normalizedKey`).
      **/
    bool sameRepo(in GitURL other) const {
        return normalizedKey == other.normalizedKey;
    }

    /// normalizedKey / sameRepo: spelling variants of one remote collapse.
    unittest {
        import unit_threaded.assertions;

        const k = GitURL("https://github.com/oca/web").normalizedKey;
        k.shouldEqual("github.com/oca/web");

        // https / https+.git / scp-form ssh / trailing slash → one key.
        GitURL("https://github.com/oca/web.git").normalizedKey.shouldEqual(k);
        GitURL("git@github.com:oca/web.git").normalizedKey.shouldEqual(k);
        GitURL("https://github.com/oca/web/").normalizedKey.shouldEqual(k);
        // Embedded credentials and port do not change identity.
        GitURL("https://user:secret@github.com/oca/web.git")
            .normalizedKey.shouldEqual(k);
        GitURL("ssh://git@github.com:2222/oca/web.git")
            .normalizedKey.shouldEqual(k);
        // Host and path are case-folded.
        GitURL("https://GitHub.com/OCA/web").normalizedKey.shouldEqual(k);

        // Different repo → different key.
        GitURL("https://github.com/oca/server").normalizedKey.shouldNotEqual(k);

        GitURL("git@github.com:oca/web.git")
            .sameRepo(GitURL("https://github.com/oca/web")).shouldBeTrue;
        GitURL("https://github.com/oca/web")
            .sameRepo(GitURL("https://github.com/oca/server")).shouldBeFalse;

        // Local repositories key by absolute path; trailing slash ignored,
        // case preserved.
        GitURL("file:///tmp/repo").normalizedKey.shouldEqual("/tmp/repo");
        GitURL("file:///tmp/repo/").normalizedKey
            .shouldEqual(GitURL("file:///tmp/repo").normalizedKey);
        GitURL(Path("/tmp/Repo")).normalizedKey.shouldEqual("/tmp/Repo");
        // A local path never collides with a remote key.
        GitURL(Path("/tmp/repo"))
            .sameRepo(GitURL("https://github.com/tmp/repo")).shouldBeFalse;
    }

    /** Split path on segments
      **/
    string[] toPathSegments() const {
        string[] path_segments;
        foreach(p; path.splitter("/"))
            path_segments ~= p;
        return path_segments;
    }

    /** Apply CI rewrites for Git URL
      **/
    auto applyCIRewrites() const {
        // Local repositories are never subject to CI credential rewrites.
        if (isLocal)
            return this;

        // If it is not running on gitlab CI at CI_JOB_TOKEN_GIT_HOST,
        // then no need to apply rewrites
        if (!environment.get("GITLAB_CI"))
            return this;
        if (!environment.get("CI_JOB_TOKEN_GIT_HOST"))
            return this;
        if (!environment.get("CI_JOB_TOKEN"))
            return this;
        if (environment["CI_JOB_TOKEN_GIT_HOST"] != host)
            return this;

        GitURL result = this;
        if ((scheme == "https" || scheme == "http") && !user && !password) {
            result._user = "gitlab-ci-token";
            result._password = environment.get("CI_JOB_TOKEN");
        } else if (scheme == "ssh" && (user == "git" || user.length == 0) && !password) {
            // Also without a user, which cannot work over ssh in CI anyway.
            result._scheme = "https";
            result._user = "gitlab-ci-token";
            result._password = environment.get("CI_JOB_TOKEN");
        } else if (!scheme && !user && !password) {
            result._scheme = "https";
            result._user = "gitlab-ci-token";
            result._password = environment.get("CI_JOB_TOKEN");
        }

        return result;
    }

    /** String representation of the URL without the user and the password,
      * for logging and display. To persist a URL, use
      * `toUrl(no_credentials: true)`, which keeps an ssh user.
      **/
    string toString() const {
        // Local paths carry no credentials, so the clone-ready form is also
        // the safe display form.
        if (isLocal)
            return "file://" ~ _path;

        string res;
        if (scheme)
            res ~= "%s://".format(scheme);

        res ~= host;
        if (port) res ~= ":%s".format(port);

        res ~= "/" ~ path;
        return res;
    }

    unittest {
        import unit_threaded.assertions;

        GitURL("github.com/katyukha/thepath.git").shouldEqual(GitURL("github.com/katyukha/thepath.git"));
        GitURL("github.com/katyukha/thepath.git").shouldEqual(GitURL("github.com/katyukha/thepath"));
        GitURL("github.com/katyukha/thepath.git").shouldNotEqual(GitURL("github.com/katyukha/theprocess"));
    }

    /// toString strips credentials; toUrl keeps them for cloning.
    unittest {
        import unit_threaded.assertions;

        // Credential-bearing URL: toUrl keeps user:password, toString drops it.
        with (GitURL("https://gitlab+deploy-token-42:some+token-s@gitlab.crnd.pro/crnd/crnd-account")) {
            toUrl.shouldEqual(
                "https://gitlab+deploy-token-42:some+token-s@gitlab.crnd.pro/crnd/crnd-account");
            toString.shouldEqual("https://gitlab.crnd.pro/crnd/crnd-account");
        }

        // SSH url: conventional 'git@' user is stripped from toString too.
        GitURL("git@gitlab.crnd.pro:crnd-opensource/crnd-web.git")
            .toString.shouldEqual("ssh://gitlab.crnd.pro/crnd-opensource/crnd-web");

        // No credentials: toString matches toUrl.
        with (GitURL("https://github.com/katyukha/thepath.git")) {
            toString.shouldEqual("https://github.com/katyukha/thepath");
            toString.shouldEqual(toUrl);
        }

        // no_credentials: the password and an http(s) user go, an ssh user stays.
        GitURL("https://gitlab+deploy-token-42:some+token-s@gitlab.crnd.pro/crnd/crnd-account")
            .toUrl(no_credentials: true).shouldEqual("https://gitlab.crnd.pro/crnd/crnd-account");
        GitURL("https://ghp_token@github.com/owner/repo")
            .toUrl(no_credentials: true).shouldEqual("https://github.com/owner/repo");
        GitURL("git@gitlab.crnd.pro:crnd-opensource/crnd-web.git")
            .toUrl(no_credentials: true).shouldEqual("ssh://git@gitlab.crnd.pro/crnd-opensource/crnd-web");
        GitURL("ssh://git:secret@gitlab.crnd.pro:2222/crnd/repo")
            .toUrl(no_credentials: true).shouldEqual("ssh://git@gitlab.crnd.pro:2222/crnd/repo");
    }

    /// Local repositories: created via the Path constructor or an explicit
    /// absolute file:// URL; everything else path-looking is rejected loudly.
    unittest {
        import unit_threaded.assertions;
        import odood.exception: OdoodException;

        // Path constructor — the canonical way to build a local git URL.
        with (GitURL(Path("/tmp/some-repo"))) {
            isLocal.shouldBeTrue;
            scheme.shouldEqual("file");
            host.shouldBeNull;
            user.shouldBeNull;
            password.shouldBeNull;
            path.shouldEqual("/tmp/some-repo");
            toUrl.shouldEqual("file:///tmp/some-repo");
            toString.shouldEqual("file:///tmp/some-repo");
        }

        // Explicit file:// URL string is equivalent.
        with (GitURL("file:///tmp/some-repo")) {
            isLocal.shouldBeTrue;
            scheme.shouldEqual("file");
            path.shouldEqual("/tmp/some-repo");
            toUrl.shouldEqual("file:///tmp/some-repo");
        }

        // Rendered form parses back to the same target (stable round-trip),
        // e.g. through serialization in assembly specs.
        GitURL(GitURL(Path("/tmp/some-repo")).toString)
            .path.shouldEqual("/tmp/some-repo");

        // Relative paths are not supported: they cannot be expressed as
        // file:// URLs and their meaning depends on the current directory.
        GitURL(Path("some/relative/repo")).shouldThrow!OdoodException;
        GitURL("file://relative/repo").shouldThrow!OdoodException;

        // Bare filesystem-path strings are rejected — no guessing; the Path
        // constructor (or file://) is the only way to make a local git URL.
        GitURL("/tmp/some-repo").shouldThrow!OdoodException;
        GitURL("./some/repo").shouldThrow!OdoodException;
        GitURL("../some/repo").shouldThrow!OdoodException;

        // CI credential rewrites never touch local repositories.
        GitURL(Path("/tmp/some-repo")).applyCIRewrites.toUrl.shouldEqual(
            "file:///tmp/some-repo");

        // Remote forms are unaffected by local-path handling.
        GitURL("https://github.com/katyukha/thepath.git").isLocal.shouldBeFalse;
    }
}

///
unittest {
    import unit_threaded.assertions;
    with (GitURL("https://github.com/katyukha/thepath.git")) {
        scheme.shouldEqual("https");
        host.shouldEqual("github.com");
        path.shouldEqual("katyukha/thepath");
        port.shouldBeNull;
        user.shouldBeNull;
        password.shouldBeNull;
        toUrl.shouldEqual("https://github.com/katyukha/thepath");
    }

    with (GitURL("github.com/katyukha/thepath.git")) {
        scheme.shouldBeNull;
        host.shouldEqual("github.com");
        path.shouldEqual("katyukha/thepath");
        port.shouldBeNull;
        user.shouldBeNull;
        password.shouldBeNull;
        toUrl.shouldEqual("github.com/katyukha/thepath");
    }

    with (GitURL("git@gitlab.crnd.pro:crnd-opensource/crnd-web.git")) {
        scheme.shouldEqual("ssh");
        host.shouldEqual("gitlab.crnd.pro");
        path.shouldEqual("crnd-opensource/crnd-web");
        port.shouldBeNull;
        user.shouldEqual("git");
        password.shouldBeNull;
        toUrl.shouldEqual("ssh://git@gitlab.crnd.pro/crnd-opensource/crnd-web");
    }

    with (GitURL("git@gitlab.crnd.pro:crnd/crnd-account")) {
        scheme.shouldEqual("ssh");
        host.shouldEqual("gitlab.crnd.pro");
        path.shouldEqual("crnd/crnd-account");
        port.shouldBeNull;
        user.shouldEqual("git");
        password.shouldBeNull;
        toUrl.shouldEqual("ssh://git@gitlab.crnd.pro/crnd/crnd-account");
    }

    with (GitURL("https://gitlab+deploy-token-42:some+token-s@gitlab.crnd.pro/crnd/crnd-account")) {
        scheme.shouldEqual("https");
        host.shouldEqual("gitlab.crnd.pro");
        path.shouldEqual("crnd/crnd-account");
        port.shouldBeNull;
        user.shouldEqual("gitlab+deploy-token-42");
        password.shouldEqual("some+token-s");
        toUrl.shouldEqual("https://gitlab+deploy-token-42:some+token-s@gitlab.crnd.pro/crnd/crnd-account");
    }
}

/// Test CI integration
unittest {
    import unit_threaded.assertions;

    environment.get("CI_JOB_TOKEN_GIT_HOST").shouldBeNull;

    // CI not configured in env, thus no rewrites have to be applied
    with (GitURL("https://gitlab.test.com/katyukha/thepath.git").applyCIRewrites) {
        scheme.shouldEqual("https");
        host.shouldEqual("gitlab.test.com");
        path.shouldEqual("katyukha/thepath");
        port.shouldBeNull;
        user.shouldBeNull;
        password.shouldBeNull;
        toUrl.shouldEqual("https://gitlab.test.com/katyukha/thepath");
    }

    auto save_env = environment.toAA;
    environment["GITLAB_CI"] = "1";
    environment["CI_JOB_TOKEN_GIT_HOST"] = "gitlab.test.com";
    environment["CI_JOB_TOKEN"] = "gitlab-token-x1";
    scope(exit) {
        // Restore env on exit
        if ("GITLAB_CI" in save_env)
            environment["GITLAB_CI"] = save_env["GITLAB_CI"];
        else
            environment.remove("GITLAB_CI");

        if ("CI_JOB_TOKEN" in save_env)
            environment["CI_JOB_TOKEN"] = save_env["CI_JOB_TOKEN"];
        else
            environment.remove("CI_JOB_TOKEN");

        if ("CI_JOB_TOKEN_GIT_HOST" in save_env)
            environment["CI_JOB_TOKEN_GIT_HOST"] = save_env["CI_JOB_TOKEN_GIT_HOST"];
        else
            environment.remove("CI_JOB_TOKEN_GIT_HOST");
    }

    with (GitURL("https://gitlab.test.com/katyukha/thepath.git").applyCIRewrites) {
        scheme.shouldEqual("https");
        host.shouldEqual("gitlab.test.com");
        path.shouldEqual("katyukha/thepath");
        port.shouldBeNull;
        user.shouldEqual("gitlab-ci-token");
        password.shouldEqual("gitlab-token-x1");
        toUrl.shouldEqual(
            "https://gitlab-ci-token:gitlab-token-x1@gitlab.test.com/katyukha/thepath");
    }

    with (GitURL("gitlab.test.com/katyukha/thepath.git").applyCIRewrites) {
        scheme.shouldEqual("https");
        host.shouldEqual("gitlab.test.com");
        path.shouldEqual("katyukha/thepath");
        port.shouldBeNull;
        user.shouldEqual("gitlab-ci-token");
        password.shouldEqual("gitlab-token-x1");
        toUrl.shouldEqual(
            "https://gitlab-ci-token:gitlab-token-x1@gitlab.test.com/katyukha/thepath");
    }

    with (GitURL("git@gitlab.test.com:katyukha/thepath.git").applyCIRewrites) {
        scheme.shouldEqual("https");
        host.shouldEqual("gitlab.test.com");
        path.shouldEqual("katyukha/thepath");
        port.shouldBeNull;
        user.shouldEqual("gitlab-ci-token");
        password.shouldEqual("gitlab-token-x1");
        toUrl.shouldEqual(
            "https://gitlab-ci-token:gitlab-token-x1@gitlab.test.com/katyukha/thepath");
    }

    // An ssh URL without a user is rewritten too; another user is left alone.
    GitURL("ssh://gitlab.test.com/katyukha/thepath").applyCIRewrites.toUrl.shouldEqual(
        "https://gitlab-ci-token:gitlab-token-x1@gitlab.test.com/katyukha/thepath");
    GitURL("ssh://someone@gitlab.test.com/katyukha/thepath").applyCIRewrites.toUrl.shouldEqual(
        "ssh://someone@gitlab.test.com/katyukha/thepath");

    // Other hosts must not be changed
    with (GitURL("git@gitlab.crnd.pro:crnd-opensource/crnd-web.git").applyCIRewrites) {
        scheme.shouldEqual("ssh");
        host.shouldEqual("gitlab.crnd.pro");
        path.shouldEqual("crnd-opensource/crnd-web");
        port.shouldBeNull;
        user.shouldEqual("git");
        password.shouldBeNull;
        toUrl.shouldEqual("ssh://git@gitlab.crnd.pro/crnd-opensource/crnd-web");
    }

    with (GitURL("git@gitlab.crnd.pro:crnd/crnd-account").applyCIRewrites) {
        scheme.shouldEqual("ssh");
        host.shouldEqual("gitlab.crnd.pro");
        path.shouldEqual("crnd/crnd-account");
        port.shouldBeNull;
        user.shouldEqual("git");
        password.shouldBeNull;
        toUrl.shouldEqual("ssh://git@gitlab.crnd.pro/crnd/crnd-account");
    }
}



/** The userinfo (`user` or `user:password`) of a git target given as a
  * string. Only the authority counts, the part between `://` and the next
  * `/`: an `@` after it belongs to the path. Targets without `://` (scp form,
  * local paths) have no place for a password and have none.
  **/
private auto findUserinfo(in string target) pure @safe {
    import std.string: indexOf, lastIndexOf;
    import std.typecons: Nullable, nullable;

    static struct Userinfo {
        bool http;          /// http(s) URL, where the user may be a token
        string user;
        string password;
        size_t start;       /// `target[start .. end]` is the userinfo and its `@`
        size_t end;
    }

    immutable scheme_end = target.indexOf("://");
    if (scheme_end < 0)
        return Nullable!Userinfo.init;
    immutable start = scheme_end + 3;
    immutable rest = target[start .. $];
    immutable slash = rest.indexOf('/');
    immutable authority = slash < 0 ? rest : rest[0 .. slash];
    immutable at = authority.lastIndexOf('@');
    if (at < 0)
        return Nullable!Userinfo.init;

    immutable scheme = target[0 .. scheme_end].toLower;
    immutable userinfo = authority[0 .. at];
    immutable colon = userinfo.indexOf(':');
    return Userinfo(
        http: scheme == "http" || scheme == "https",
        user: colon < 0 ? userinfo : userinfo[0 .. colon],
        password: colon < 0 ? null : userinfo[colon + 1 .. $],
        start: start,
        end: start + at + 1).nullable;
}

/** Remove the credentials from a git target given as a string, for error
  * messages and logs. The rule is the one of `GitURL.hasCredentials`: the
  * password of any URL goes, and so does the user of an http(s) URL, which
  * may be a token. Targets without `://` (scp form, local paths) are
  * returned as given.
  **/
package(odood) string redactCredentials(in string target) pure @safe {
    const found = findUserinfo(target);
    if (found.isNull)
        return target;
    const info = found.get;
    immutable kept_user = info.http ? "" : info.user ~ "@";
    return target[0 .. info.start] ~ kept_user ~ target[info.end .. $];
}

/** The values `redactCredentials` removes from `target`, to mask with
  * `Process.setMasked` where the target is passed to git: the password of
  * any URL, and the user of an http(s) URL.
  **/
package(odood) string[] credentialValues(in string target) pure @safe {
    const found = findUserinfo(target);
    if (found.isNull)
        return null;
    const info = found.get;
    string[] res;
    if (info.http && info.user.length > 0)
        res ~= info.user;
    if (info.password.length > 0)
        res ~= info.password;
    return res;
}

///
unittest {
    import unit_threaded.assertions;

    credentialValues("https://user:TOKEN@host.test/o/r").shouldEqual(["user", "TOKEN"]);
    credentialValues("HTTPS://TOKEN@host.test:8443/o/r.git").shouldEqual(["TOKEN"]);
    credentialValues("ssh://git:TOKEN@host.test/o/r").shouldEqual(["TOKEN"]);
    credentialValues("ssh://git@host.test/o/r").length.shouldEqual(0);
    credentialValues("https://host.test/o/r@v2").length.shouldEqual(0);
    credentialValues("git@host.test:o/r.git").length.shouldEqual(0);
    credentialValues("/srv/git/repo").length.shouldEqual(0);
}

///
unittest {
    import unit_threaded.assertions;

    redactCredentials("https://user:TOKEN@host.test/o/r")
        .shouldEqual("https://host.test/o/r");
    redactCredentials("HTTPS://TOKEN@host.test:8443/o/r.git")
        .shouldEqual("HTTPS://host.test:8443/o/r.git");
    redactCredentials("ssh://git:TOKEN@host.test/o/r")
        .shouldEqual("ssh://git@host.test/o/r");
    redactCredentials("ssh://git@host.test/o/r").shouldEqual("ssh://git@host.test/o/r");
    // An '@' after the host is part of the path, not a user.
    redactCredentials("https://host.test/o/r@v2").shouldEqual("https://host.test/o/r@v2");
    redactCredentials("git@host.test:o/r.git").shouldEqual("git@host.test:o/r.git");
    redactCredentials("/srv/git/repo").shouldEqual("/srv/git/repo");
}
