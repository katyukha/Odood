module odood.lib.repository;

private import std.regex;
private import std.exception: enforce;
private import std.format: format;
private import std.logger;

private import thepath: Path;

private import odood.lib.utils: runCmdE;
private import odood.lib.project: Project;
private import odood.lib.exception: OdoodException;


// Struct to handle git urls
struct GitURL {
    string scheme;
    string user;
    string password;
    string host;
    string port;
    string path;

    @disable this();

    this(in string url) {
        auto immutable re_git_url = ctRegex!(
            `^((?P<scheme>http|https|ssh|git)://)?((?P<user>[\w\-\.]+)(:(?P<password>[\w\-\.]+))?@)?(?P<host>[\w\-\.]+)(:(?P<port>\d+))?(/|:)((?P<path>[\w\-\/\.]+?)(?:\.git)?)$`);
        auto re_match = url.matchFirst(re_git_url);
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
        }

        with (GitURL("git@gitlab.crnd.pro:crnd-opensource/crnd-web.git")) {
            scheme.shouldEqual("ssh");
            host.shouldEqual("gitlab.crnd.pro");
            path.shouldEqual("crnd-opensource/crnd-web");
            port.shouldBeNull;
            user.shouldEqual("git");
            password.shouldBeNull;
        }

        with (GitURL("git@gitlab.crnd.pro:crnd/crnd-account")) {
            scheme.shouldEqual("ssh");
            host.shouldEqual("gitlab.crnd.pro");
            path.shouldEqual("crnd/crnd-account");
            port.shouldBeNull;
            user.shouldEqual("git");
            password.shouldBeNull;
        }
    }

}


struct AddonRepository {
    private const Path _path;

    @disable this();

    this(in Path path) {
        _path = path;
    }

    @property path() const {
        return _path;
    }

    // TODO: May be it have sense to create separate entity AddonRepoManager
    static auto clone(
            in Project project,
            in string url,
            in string branch) {
        import std.algorithm: splitter;
        import std.conv: to;
        auto git_url = GitURL(url);

        string[] path_segments;
        foreach(p; git_url.path.splitter("/"))
            path_segments ~= p;
        auto dest = project.directories.repositories.join(path_segments);
        enforce!OdoodException(
            dest.isValid,
            "Cannot compute destination for git repo %s");
        enforce!OdoodException(
            !dest.join(".git").exists,
            "It seems that repo %s already clonned!".format(url));
        infof("Clonning repository (branch=%s): %s", branch, url);
        runCmdE(["git", "clone", "-b", branch, url, dest.toString]);
        return AddonRepository(dest);
    }
}
