module odood.lib.addons.repository;

private import std.logger: warningf, infof;
private import std.exception: enforce;

private import thepath: Path;

private import odood.lib.project: Project;
private import odood.exception: OdoodException;
private import odood.utils.git: GitRepository, parseGitURL, gitClone;
private import theprocess;

// TODO: may be move pre-commit logic somewhere else?

// Configuration files for pre-commit for Odoo version 17
immutable string ODOO_PRE_COMMIT_17_PRECOMMIT = import(
    "pre-commit/17.0/pre-commit-config.yaml");
immutable string ODOO_PRE_COMMIT_17_ESLINT = import(
    "pre-commit/17.0/eslintrc.yml");
immutable string ODOO_PRE_COMMIT_17_FLAKE8 = import(
    "pre-commit/17.0/flake8");
immutable string ODOO_PRE_COMMIT_17_ISORT = import(
    "pre-commit/17.0/isort.cfg");
immutable string ODOO_PRE_COMMIT_17_PYLINT = import(
    "pre-commit/17.0/pylintrc");


class AddonRepository : GitRepository{
    private const Project _project;

    @disable this();

    this(in Project project, in Path path) {
        super(path);
        _project = project;
    }

    auto project() const => _project;

    /// Check if repository has pre-commit configuration.
    bool hasPreCommitConfig() const {
        return path.join(".pre-commit-config.yaml").exists;
    }

    /// Initialize pre-commit for this repository
    void initPreCommit(in bool force=false, in bool setup=true) const {
        enforce!OdoodException(
            force || !hasPreCommitConfig,
            "Cannot init pre-commit. Configuration already exists");
        enforce!OdoodException(
            project.odoo.serie == 17,
            "This feature is available only for Odoo 17 at the moment!");
        infof("Initializing pre-commit for %s repo!", path);
        this.path.join(".pre-commit-config.yaml").writeFile(
            ODOO_PRE_COMMIT_17_PRECOMMIT);
        this.path.join(".eslintrc.yml").writeFile(
            ODOO_PRE_COMMIT_17_ESLINT);
        this.path.join(".flake8").writeFile(
            ODOO_PRE_COMMIT_17_FLAKE8);
        this.path.join(".isort.cfg").writeFile(
            ODOO_PRE_COMMIT_17_ISORT);
        this.path.join(".pylintrc").writeFile(
            ODOO_PRE_COMMIT_17_PYLINT);

        if (setup)
            setUpPreCommit();
    }

    /// Setup Precommit if needed
    void setUpPreCommit() const {
        if (hasPreCommitConfig) {
            infof("Setting up pre-commit for %s repo!", path);
            _project.venv.installPyPackages("pre-commit");
            _project.venv.runE(["pre-commit", "install"]);
        } else {
            warningf(
                "Cannot set up pre-commit for repository %s, " ~
                "because it does not have pre-commit configuration!",
                path);
        }
    }

    /// Return array of odoo addons, found in this repo.
    /// this method searches for addons recursively by default.
    auto addons(in bool recursive=true) const {
        return project.addons.scan(path, recursive);
    }
}
