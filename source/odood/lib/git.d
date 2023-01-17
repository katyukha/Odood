module odood.lib.git;

private import std.logger;
private import std.regex;
private import std.exception: enforce;
private import std.format: format;

private import thepath: Path;

private import odood.lib.utils: runCmdE;
private import odood.lib.exception: OdoodException;

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

        res ~= path;
        return res;
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

    with (GitURL("git@gitlab.crnd.pro:crnd-opensource/crnd-web.git")) {
        scheme.shouldEqual("ssh");
        host.shouldEqual("gitlab.crnd.pro");
        path.shouldEqual("crnd-opensource/crnd-web");
        port.shouldBeNull;
        user.shouldEqual("git");
        password.shouldBeNull;
        toUrl.shouldEqual("git@gitlab.crnd.pro:crnd-opensource/crnd-web");
    }

    with (GitURL("git@gitlab.crnd.pro:crnd/crnd-account")) {
        scheme.shouldEqual("ssh");
        host.shouldEqual("gitlab.crnd.pro");
        path.shouldEqual("crnd/crnd-account");
        port.shouldBeNull;
        user.shouldEqual("git");
        password.shouldBeNull;
        toUrl.shouldEqual("git@gitlab.crnd.pro:crnd/crnd-account");
    }
}


/// Clone git repository to provided destination directory
void gitClone(in GitURL repo, in Path dest, in string branch) {
    enforce!OdoodException(
        dest.isValid,
        "Cannot clone repo %s! Destination path %s is invalid!".format(
            repo, dest));
    enforce!OdoodException(
        !dest.join(".git").exists,
        "It seems that repo %s already clonned to %s!".format(repo, dest));
    infof("Clonning repository (branch=%s): %s", branch, repo);

    // TODO: Make branch optional
    runCmdE(["git", "clone", "-b", branch, repo.toUrl, dest.toString]);
}
