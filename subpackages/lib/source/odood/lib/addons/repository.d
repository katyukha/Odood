module odood.lib.addons.repository;

private import std.logger: warningf;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.exception: OdoodException;
private import odood.utils.git: GitRepository, parseGitURL, gitClone;
private import theprocess;


class AddonRepository : GitRepository{
    private const Project _project;

    @disable this();

    this(in Project project, in Path path) {
        super(path);
        _project = project;
    }

    /// Check if repository has pre-commit configuration.
    bool hasPreCommitConfig() const {
        return path.join(".pre-commit-config.yaml").exists;
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
                path);
        }
    }
}
