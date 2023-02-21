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
    private const Project _project;
    private const Path _path;

    @disable this();

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

}
