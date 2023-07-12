module odood.utils.git;

private import std.logger;
private import std.regex: ctRegex, matchFirst;
private import std.exception: enforce;
private import std.format: format;

private import thepath: Path;

private import odood.exception: OdoodException;
private import theprocess;


// TODO: Add parsing of branch name from url
/// Regex for parsing git URL
auto immutable RE_GIT_URL = ctRegex!(
    `^((?P<scheme>http|https|ssh|git)://)?((?P<user>[\w\-\.]+)(:(?P<password>[\w\-\.]+))?@)?(?P<host>[\w\-\.]+)(:(?P<port>\d+))?(/|:)((?P<path>[\w\-\/\.]+?)(?:\.git)?)$`);


/// Struct to handle git urls
private struct GitURL {
    string scheme;
    string user;
    string password;
    string host;
    string port;
    string path;

    @disable this();

    this(in string url) {
        auto re_match = url.matchFirst(RE_GIT_URL);
        enforce!OdoodException(
            !re_match.empty || !re_match["path"] || !re_match["host"],
            "Cannot parse git url '%s'".format(url));

        user = re_match["user"];
        password = re_match["password"];
        host = re_match["host"];
        port = re_match["port"];
        path = re_match["path"];

        // If no scheme detected, but there is user in the URL, then
        // it seems to be SSH url
        if (!re_match["scheme"] && user)
            // TODO: may be use separate regex for SSH urls
            scheme = "ssh";
        else
            scheme = re_match["scheme"];
    }

    /** Convert to string that is suitable to pass to git clone
      **/
    string toUrl() const {
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
        import std.algorithm: splitter;
        string[] path_segments;
        foreach(p; path.splitter("/"))
            path_segments ~= p;
        return path_segments;
    }

    /** Apply CI rewrites for Git URL
      **/
    auto applyCIRewrites() const {
        import std.process: environment;

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
            result.user = "gitlab-ci-token";
            result.password = environment.get("CI_JOB_TOKEN");
        } else if (scheme == "ssh" && user == "git" && !password) {
            result.scheme = "https";
            result.user = "gitlab-ci-token";
            result.password = environment.get("CI_JOB_TOKEN");
        } else if (!scheme && !user && !password) {
            result.scheme = "https";
            result.user = "gitlab-ci-token";
            result.password = environment.get("CI_JOB_TOKEN");
        }

        return result;
    }

    string toString() const {
        return toUrl();
    }
}


/// Parse git url for further processing
GitURL parseGitURL(in string url) {
    return GitURL(url);
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
}

/// Test CI integration
unittest {
    import unit_threaded.assertions;
    import std.process: environment;

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


/// Clone git repository to provided destination directory
void gitClone(
        in GitURL repo,
        in Path dest,
        in string branch,
        in bool single_branch=false) {
    enforce!OdoodException(
        dest.isValid,
        "Cannot clone repo %s! Destination path %s is invalid!".format(
            repo, dest));
    enforce!OdoodException(
        !dest.join(".git").exists,
        "It seems that repo %s already clonned to %s!".format(repo, dest));
    infof("Clonning repository (branch=%s): %s", branch, repo);

    // TODO: Make branch optional
    string[] git_options = ["clone", "-b", branch];
    if (single_branch)
        git_options ~= ["--single-branch"];
    git_options ~= [repo.applyCIRewrites.toUrl, dest.toString];
    Process("git")
        .setArgs(git_options)
        .execute()
        .ensureStatus();
}

/** Check if specified path is git repository
  **/
bool isGitRepo(in Path path) {
    if (path.join(".git").exists)
        return true;

    const auto result = Process("git")
        .setArgs("rev-parse", "--git-dir")
        .setWorkDir(path)
        .execute();
    if (result.status == 0)
        return true;

    return false;
}
