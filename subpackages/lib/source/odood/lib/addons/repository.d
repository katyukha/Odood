module odood.lib.addons.repository;

private import std.regex;
private import std.exception: enforce;
private import std.format: format;
private import std.logger;
private static import std.process;

private import thepath: Path;

private import odood.lib.utils: runCmdE;
private import odood.lib.project: Project;
private import odood.lib.exception: OdoodException;
private import odood.lib.git: parseGitURL, gitClone;


// TODO: Do we need this struct?
class AddonRepository {
    private const Project _project;
    private const Path _path;

    //@disable this();

    this(in Project project, in Path path) {
        _project = project;
        _path = path;
    }

    @property path() const {
        return _path;
    }

    /// Check if repository has pre-commit configuration.
    bool hasPreCommitConfig() const {
        return _path.join(".pre-commit-config.yaml").exists;
    }

    /// Setup Precommit if needed
    void setUpPreCommit() {
        if (hasPreCommitConfig) {
            _project.venv.installPyPackages("pre-commit");
            _project.venv.runE(["pre-commit", "install"]);
        } else {
            warningf(
                "Cannot set up pre-commit for repository %s, " ~
                "because it does not have pre-commit configuration!",
                _path);
        }
    }

    /** Find the name of current git branch for this repo
      **/
    string getCurrBranch() {
        import std.string: chompPrefix, strip;
        string git_ref = runCmdE(
            ["git", "symbolic-ref", "-q", "HEAD"],
            _path,
            null,
            std.process.Config.stderrPassThrough,
        ).output;

        return git_ref.strip().chompPrefix("refs/heads/");
    }

    /** Fetch remote 'origin'
      **/
    void fetchOrigin() {
        runCmdE(["git", "fetch", "origin"], _path);
    }

    /// ditto
    void fetchOrigin(in string branch) {
        runCmdE(["git", "fetch", "origin", branch], _path);
    }

    /** Switch repo to specified branch
      **/
    void switchBranchTo(in string branch_name) {
        runCmdE(["git", "checkout", branch_name], _path);

    }
}
