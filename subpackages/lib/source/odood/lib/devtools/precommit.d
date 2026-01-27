module odood.lib.devtools.precommit;

private import std.logger: warningf, infof;
private import std.format: format;
private import std.exception: enforce;

private import odood.lib.addons.repository: AddonRepository;
private import odood.lib.project: Project;
private import odood.exception: OdoodException;

private import darktemple: renderFile;


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
void initPreCommit(in Project project, in AddonRepository repo, in bool force=false, in bool setup=true) {
    enforce!OdoodException(
        force || !repo.hasPreCommitConfig,
        "Cannot init pre-commit. Configuration already exists");
    infof("Initializing pre-commit for %s repo!", repo.path);
    repo.path.join(".pre-commit-config.yaml").writeFile(
        renderFile!("pre-commit/pre-commit-config.yaml", project, repo));
    repo.path.join(".eslintrc.yml").writeFile(
        renderFile!("pre-commit/eslintrc.yml", project, repo));
    repo.path.join(".flake8").writeFile(
        renderFile!("pre-commit/flake8", project, repo));
    repo.path.join(".isort.cfg").writeFile(
        renderFile!("pre-commit/isort.cfg", project, repo));
    repo.path.join(".pylintrc").writeFile(
        renderFile!("pre-commit/pylintrc", project, repo));

    if (setup)
        project.setUpPreCommit(repo);
}


/** Set up pre-commit for specified repository.
  * This means, installing pre-commit in virtualenv of related project,
  * and running "pre-commit install" command.
  *
  * Params:
  *     repo = repository to initialize pre-commit for.
  **/
void setUpPreCommit(in Project project, in AddonRepository repo) {
    if (repo.hasPreCommitConfig) {
        infof("Setting up pre-commit for %s repo!", repo.path);
        project.venv.installPyPackages("pre-commit");
        project.venv.runner
            .inWorkDir(repo.path)
            .withArgs("pre-commit", "install")
            .execute
            .ensureOk!OdoodException(true);
    } else {
        warningf(
            "Cannot set up pre-commit for repository %s, " ~
            "because it does not have pre-commit configuration!",
            repo.path);
    }
}


void updatePreCommit(in Project project, in AddonRepository repo) {
    enforce!OdoodException(
        repo.hasPreCommitConfig,
        "Repo %s does not have pre-commit configuration!".format(repo.path));
    project.venv.runner
        .withArgs("pre-commit", "autoupdate")
        .execute
        .ensureOk!OdoodException(true);
}
