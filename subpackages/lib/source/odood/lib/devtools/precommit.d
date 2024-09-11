module odood.lib.devtools.precommit;

private import std.logger: warningf, infof;
private import std.exception: enforce;

private import odood.lib.addons.repository: AddonRepository;
private import odood.exception: OdoodException;


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


/** Check if repository has precommit configuration file
  *
  * Params:
  *     repo = repository to check
  *
  * Returns:
  *     true if repository has pre-commit config file, otherwise false
  **/
bool hasPreCommitConfig(in AddonRepository repo) {
    return repo.path.join(".pre-commit-config.yaml").exists;
}


/** Initialize pre-commit for specified repo.
  *
  * Params:
  *     repo = repository to initialize pre-commit for.
  *     force = if set to true, rewrite already existing pre-commit config.
  *     setup = if set to true, then automatically set up pre-commit according to new configuration.
  **/
void initPreCommit(in AddonRepository repo, in bool force=false, in bool setup=true) {
    enforce!OdoodException(
        force || !repo.hasPreCommitConfig,
        "Cannot init pre-commit. Configuration already exists");
    enforce!OdoodException(
        repo.project.odoo.serie == 17,
        "This feature is available only for Odoo 17 at the moment!");
    infof("Initializing pre-commit for %s repo!", repo.path);
    repo.path.join(".pre-commit-config.yaml").writeFile(
        ODOO_PRE_COMMIT_17_PRECOMMIT);
    repo.path.join(".eslintrc.yml").writeFile(
        ODOO_PRE_COMMIT_17_ESLINT);
    repo.path.join(".flake8").writeFile(
        ODOO_PRE_COMMIT_17_FLAKE8);
    repo.path.join(".isort.cfg").writeFile(
        ODOO_PRE_COMMIT_17_ISORT);
    repo.path.join(".pylintrc").writeFile(
        ODOO_PRE_COMMIT_17_PYLINT);

    if (setup)
        setUpPreCommit(repo);
}


/** Set up pre-commit for specified repository.
  * This means, installing pre-commit in virtualenv of related project,
  * and running "pre-commit install" command.
  *
  * Params:
  *     repo = repository to initialize pre-commit for.
  **/
void setUpPreCommit(in AddonRepository repo) {
    if (repo.hasPreCommitConfig) {
        infof("Setting up pre-commit for %s repo!", repo.path);
        repo.project.venv.installPyPackages("pre-commit");
        repo.project.venv.runE(["pre-commit", "install"]);
    } else {
        warningf(
            "Cannot set up pre-commit for repository %s, " ~
            "because it does not have pre-commit configuration!",
            repo.path);
    }
}
