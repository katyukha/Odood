module odood.utils.git.repository;

private import std.regex;
private import std.exception: enforce;
private import std.format: format;
private import std.logger;
private import std.typecons: Nullable, nullable;
private import std.string: chompPrefix, strip;
private static import std.process;

private import thepath: Path;

private import odood.exception: OdoodException;
private import odood.utils.git: parseGitURL, gitClone;
private import theprocess;


/** Simple class to manage git repositories
  **/
class GitRepository {
    private const Path _path;

    @disable this();

    this(in Path path) {
        _path = path;
    }

    /// Return path for this repo
    auto path() const => _path;

    /** Find the name of current git branch for this repo.
      *
      * Returns: Nullable!string
      *     If current branch is detected, result is non-null.
      *     If result is null, then git repository is in detached-head mode.
      **/
    Nullable!string getCurrBranch() {
        auto result = Process("git")
            .setArgs(["symbolic-ref", "-q", "HEAD"])
            .setWorkDir(_path)
            .setFlag(std.process.Config.Flags.stderrPassThrough)
            .execute();
        if (result.status == 0)
            return result.output.strip().chompPrefix("refs/heads/").nullable;
        return Nullable!(string).init;
    }

    /** Get current commit
      *
      * Returns:
      *     SHA1 hash of current commit
      **/
    string getCurrCommit() {
        return Process("git")
            .setArgs(["rev-parse", "-q", "HEAD"])
            .setWorkDir(_path)
            .setFlag(std.process.Config.stderrPassThrough)
            .execute()
            .ensureStatus(true)
            .output.strip();
    }

    /** Fetch remote 'origin'
      **/
    void fetchOrigin() {
        Process("git")
            .setArgs("fetch", "origin")
            .setWorkDir(_path)
            .execute()
            .ensureStatus(true);
    }

    /// ditto
    void fetchOrigin(in string branch) {
        Process("git")
            .setArgs("fetch", "origin", branch)
            .setWorkDir(_path)
            .execute()
            .ensureStatus(true);
    }

    /** Switch repo to specified branch
      **/
    void switchBranchTo(in string branch_name) {
        Process("git")
            .setArgs("checkout", branch_name)
            .setWorkDir(_path)
            .execute()
            .ensureStatus(true);

    }
}

