module odood.lib.devtools.precommit;

private import std.logger: warningf, infof;
private import std.format: format;
private import std.exception: enforce;

private import odood.lib.addons.repository: AddonRepository;
private import odood.lib.python.venv: VirtualEnv;
private import odood.utils.odoo.serie: OdooSerie;
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


/** Manages pre-commit configuration and hooks for a single addon repository.
  *
  * Project-free: constructed from the repository plus the virtualenv (used to
  * install and run `pre-commit`) and the Odoo serie (used when rendering the
  * linter config). This makes pre-commit management usable without a full
  * Project — see `Project.preCommit` for the convenience accessor.
  **/
struct PreCommitManager {
    private const AddonRepository _repo;
    private const VirtualEnv _venv;
    private const OdooSerie _serie;

    @disable this();

    this(in AddonRepository repo, in VirtualEnv venv, in OdooSerie serie) {
        _repo = repo;
        _venv = venv;
        _serie = serie;
    }

    /** Initialize pre-commit for the repository (Odood default config).
      *
      * Params:
      *     force = if set, overwrite an already existing pre-commit config.
      *     setup = if set, also run `setUp` after writing the config.
      **/
    void init(in bool force=false, in bool setup=true) {
        enforce!OdoodException(
            force || !_repo.hasPreCommitConfig,
            "Cannot init pre-commit. Configuration already exists");
        infof("Initializing pre-commit for %s repo!", _repo.path);

        // darktemple binds template vars by identifier name; templates use `serie`.
        const serie = _serie;
        _repo.path.join(".pre-commit-config.yaml").writeFile(
            renderFile!("pre-commit/pre-commit-config.yaml", serie));
        _repo.path.join(".eslintrc.yml").writeFile(
            renderFile!("pre-commit/eslintrc.yml", serie));
        _repo.path.join(".flake8").writeFile(
            renderFile!("pre-commit/flake8", serie));
        _repo.path.join(".isort.cfg").writeFile(
            renderFile!("pre-commit/isort.cfg", serie));
        _repo.path.join(".pylintrc").writeFile(
            renderFile!("pre-commit/pylintrc", serie));

        if (setup)
            this.setUp();
    }

    /** Initialize pre-commit with an odoo-helper-compatible (check-only) config.
      *
      * Generates check-only linting configuration (no auto-formatting) that
      * matches odoo-helper-scripts' default linting setup. Useful when migrating
      * projects from odoo-helper-scripts to Odood.
      *
      * Params:
      *     force = if set, overwrite an already existing pre-commit config.
      *     setup = if set, also run `setUp` after writing the config.
      **/
    void initOdooHelper(in bool force=false, in bool setup=true) {
        enforce!OdoodException(
            force || !_repo.hasPreCommitConfig,
            "Cannot init pre-commit. Configuration already exists");
        infof("Initializing pre-commit (odoo-helper-compat) for %s repo!", _repo.path);

        const serie = _serie;
        _repo.path.join(".pre-commit-config.yaml").writeFile(
            renderFile!("pre-commit-odoo-helper/pre-commit-config.yaml", serie));
        _repo.path.join(".eslintrc.yml").writeFile(
            renderFile!("pre-commit-odoo-helper/eslintrc.yml", serie));
        _repo.path.join(".flake8").writeFile(
            renderFile!("pre-commit-odoo-helper/flake8", serie));
        _repo.path.join(".pylintrc").writeFile(
            renderFile!("pre-commit-odoo-helper/pylintrc", serie));

        if (setup)
            this.setUp();
    }

    /** Set up pre-commit for the repository: install `pre-commit` in the
      * virtualenv and run `pre-commit install`.
      **/
    void setUp() {
        if (_repo.hasPreCommitConfig) {
            infof("Setting up pre-commit for %s repo!", _repo.path);
            _venv.installPyPackages("pre-commit");
            _venv.runner
                .inWorkDir(_repo.path)
                .withArgs("pre-commit", "install")
                .execute
                .ensureOk!OdoodException(true);
        } else {
            warningf(
                "Cannot set up pre-commit for repository %s, " ~
                "because it does not have pre-commit configuration!",
                _repo.path);
        }
    }

    /** Update pre-commit hooks in the repository (`pre-commit autoupdate`).
      **/
    void update() {
        enforce!OdoodException(
            _repo.hasPreCommitConfig,
            "Repo %s does not have pre-commit configuration!".format(_repo.path));
        _venv.runner
            .withArgs("pre-commit", "autoupdate")
            .execute
            .ensureOk!OdoodException(true);
    }
}
