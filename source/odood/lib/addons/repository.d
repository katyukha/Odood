module odood.lib.addons.repository;

private import std.regex;
private import std.exception: enforce;
private import std.format: format;
private import std.logger;

private import thepath: Path;

private import odood.lib.utils: runCmdE;
private import odood.lib.project: Project;
private import odood.lib.exception: OdoodException;
private import odood.lib.git: parseGitURL, gitClone;


// TODO: Do we need this struct?
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
        auto git_url = parseGitURL(url);

        string[] path_segments;
        foreach(p; git_url.path.splitter("/"))
            path_segments ~= p;
        auto dest = project.directories.repositories.join(path_segments);
        gitClone(git_url, dest, branch);
        return AddonRepository(dest);
    }
}
