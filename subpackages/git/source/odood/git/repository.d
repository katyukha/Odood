module odood.git.repository;

private import std.typecons: Nullable, nullable;
private import std.string: chompPrefix, strip;
private static import std.process;

private import thepath: Path;

private import odood.exception: OdoodException;
private import theprocess;
private import odood.git: getGitTopLevel;


/** Simple class to manage git repositories
  **/
class GitRepository {
    private const Path _path;

    @disable this();

    this(in Path path) {
        if (path.join(".git").exists)
            _path = path;
        else
            _path = getGitTopLevel(path);
    }

    /// Return path for this repo
    auto path() const => _path;

    /// Preconfigured runner for git CLI
    protected auto gitCmd() const {
        return Process("git")
            .inWorkDir(_path);
    }

    /** Find the name of current git branch for this repo.
      *
      * Returns: Nullable!string
      *     If current branch is detected, result is non-null.
      *     If result is null, then git repository is in detached-head mode.
      **/
    Nullable!string getCurrBranch() {
        auto result = gitCmd
            .withArgs(["symbolic-ref", "-q", "HEAD"])
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
        return gitCmd
            .withArgs(["rev-parse", "-q", "HEAD"])
            .setFlag(std.process.Config.stderrPassThrough)
            .execute()
            .ensureStatus(true)
            .output.strip();
    }

    /** Fetch remote 'origin'
      **/
    void fetchOrigin() {
        gitCmd
            .withArgs("fetch", "origin")
            .execute()
            .ensureStatus(true);
    }

    /// ditto
    void fetchOrigin(in string branch) {
        gitCmd
            .setArgs("fetch", "origin", branch)
            .execute()
            .ensureStatus(true);
    }

    /** Switch repo to specified branch
      **/
    void switchBranchTo(in string branch_name) {
        gitCmd
            .setArgs("checkout", branch_name)
            .execute()
            .ensureStatus(true);

    }

    /** Set annotation tag on current commit in repo
      **/
    void setTag(in string tag_name, in string message = null) 
    in (tag_name.length > 0) {
        // TODO: add ability to set tag on specific commit
        gitCmd
            .withArgs(
                "tag",
                "-a", tag_name,
                "-m", message.length > 0 ? message : tag_name)
            .execute()
            .ensureOk(true);
    }

    /** Pull repository
      **/
    void pull() {
        gitCmd
            .withArgs("pull")
            .execute()
            .ensureOk(true);
    }
}


