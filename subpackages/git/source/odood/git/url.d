module odood.git.url;

private import std.logger: infof;
private import std.regex: regex, matchFirst;
private import std.exception: enforce;
private import std.format: format;
private import std.process: environment;
private import std.string: startsWith;
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
      * where a clone-ready URL is required; for logging, serialization,
      * or display use `toString`, which strips credentials.
      **/
    string toUrl() const {
        if (isLocal)
            return "file://" ~ _path;

        string res;
        if (scheme)
            res ~= "%s://".format(scheme);

        if (user && password)
            res ~= "%s:%s@%s".format(user, password, host);
        else if (user)
            res ~= "%s@%s".format(user, host);
        else
            res ~= host;

        if (port) res ~= ":%s".format(port);

        res ~= "/" ~ path;
        return res;
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
        } else if (scheme == "ssh" && user == "git" && !password) {
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

    /** String representation of the URL with any embedded credentials
      * (user/password) stripped. Safe by default for logging, serialization,
      * and display. Use `toUrl` when a clone-ready URL (with credentials)
      * is required.
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

