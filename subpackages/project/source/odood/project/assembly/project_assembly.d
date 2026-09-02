module odood.project.assembly.project_assembly;

private import std.logger: infof;
private import std.array: empty, array;
private import std.algorithm: map;

private import thepath: Path;

private import odood.lib.assembly.assembly: Assembly, ASSEMBLY_REQUIREMENTS_LOCK;
private import odood.lib.assembly.source_provider_cached: AssemblySourceProviderCached;
private import odood.project: Project;
private import odood.git: GitURL;
private import odood.lib.python.venv: PyRequirements;
private import odood.project.addons.manager:
    DEFAULT_INSTALL_PY_REQUIREMENTS,
    DEFAULT_INSTALL_MANIFEST_REQUIREMENTS;


/** Project-bound assembly: wraps a project-free `Assembly` and adds the
  * operations that require a live Odoo instance — linking assembly addons into
  * the project, generating a requirements lock (via the project venv), and
  * validating addon dependencies against the project's system addons.
  *
  * Only the project-bound operations live here; the base (project-free) surface
  * is reached explicitly via the `raw` accessor. Moves to `odood:project` when
  * the subpackage split lands; the base `Assembly` stays in `odood:lib`.
  **/
class ProjectAssembly {
    private Assembly _assembly;
    private Project _project;

    this(Project project, Assembly assembly) {
        _project = project;
        _assembly = assembly;
    }

    /// The wrapped raw (project-free) assembly — base operations live here.
    @property inout(Assembly) raw() inout pure nothrow @safe => _assembly;

    /// Project this assembly is related to.
    @property project() const => _project;

    // Private shortcuts to the base members used by the operations below.
    private @property dist_dir() const => _assembly.dist_dir;
    private @property spec() const => _assembly.spec;
    private @property repo() => _assembly.repo;

    /** Fetch sources and assemble addons (base `sync`), validate dependencies
      * against the project's Odoo instance, and optionally generate a
      * requirements lock.
      **/
    void sync(in bool generate_lock=false, in bool with_odoo_requirements=false) {
        _assembly.sync();
        validateAddonsDependencies();

        if (generate_lock)
            generateRequirementsLock(with_odoo_requirements);
    }

    /** Validate that every assembly addon's dependencies are satisfiable
      * against the project's system addons (delegates to the base assembly,
      * passing the project's system addon names).
      **/
    void validateAddonsDependencies() const {
        _assembly.validateAddonsDependencies(
            _project.addons.getSystemAddonsList()
                .map!((a) => a.name)
                .array);
    }

    /** Link assembly addons into the project's custom addons.
      *
      * Remove symlinks that point to this assembly from custom addons,
      * and create only valid symlinks.
      *
      * If requirements.lock.txt exists in the assembly root, install only
      * from that file (skip per-addon requirement scanning). Otherwise,
      * gather all addon requirements and install in a single pip call.
      *
      * Params:
      *     py_requirements = collect/install from requirements.txt files
      *     manifest_requirements = collect/install from manifest python_dependencies
      *     individual_requirements = if set, install requirements per-addon
      *         instead of batched (old behavior)
      *     with_odoo_requirements = if set, include Odoo's requirements.txt
      *         in the batch install
      **/
    void link(
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS,
            in bool individual_requirements=false,
            in bool with_odoo_requirements=false) const {
        infof("Assembly Link: Cleanup old symlinks.");

        // Remove all links in custom addons that point to this assembly
        foreach(p; _project.directories.addons.walk) {
            if (p.isSymlink && p.readLink.isInside(dist_dir))
                p.remove();
        }

        auto lock_path = _assembly.path.join(ASSEMBLY_REQUIREMENTS_LOCK);
        if (lock_path.exists) {
            // Lock file present: install only from it, skip per-addon scanning
            infof("Assembly Link: Installing requirements from lock file '%s'", lock_path);
            _project.venv.installPyRequirements(lock_path);

            // Symlink addons only (no per-addon pip)
            infof("Assembly Link: Start linking");
            _project.addons.link(
                search_path: dist_dir,
                recursive: true,
                force: true,
                py_requirements: false,
                manifest_requirements: false);
        } else {
            // No lock file: use batched (or individual) install
            infof("Assembly Link: Start linking");
            PyRequirements reqs;

            // Include assembly-root requirements.txt in the batch
            if (py_requirements && _assembly.path.join("requirements.txt").exists) {
                reqs.addRequirementsFile(_assembly.path.join("requirements.txt"));
            }

            if (individual_requirements) {
                // Install assembly-root requirements first, then per-addon
                if (!reqs.empty)
                    _project.venv.installBatchPyRequirements(reqs);
                _project.addons.link(
                    search_path: dist_dir,
                    recursive: true,
                    force: true,
                    py_requirements: py_requirements,
                    manifest_requirements: manifest_requirements,
                    individual_requirements: true);
            } else {
                // Symlink only, gather requirements, batch install
                _project.addons.link(
                    search_path: dist_dir,
                    recursive: true,
                    force: true,
                    py_requirements: false,
                    manifest_requirements: false);

                // Gather addon requirements
                auto addon_reqs = _project.addons.collectPyRequirements(
                    dist_dir, true, py_requirements, manifest_requirements);
                reqs.add(addon_reqs);

                if (with_odoo_requirements
                        && _project.odoo.path.join("requirements.txt").exists) {
                    reqs.addRequirementsFile(
                        _project.odoo.path.join("requirements.txt"));
                }

                if (!reqs.empty) {
                    infof("Assembly Link: Installing python requirements (batched)");
                    _project.venv.installBatchPyRequirements(reqs);
                }
            }
        }
        infof("Assembly Link: Completed");
    }

    /** Generate requirements.lock.txt for this assembly.
      *
      * Scans all addons and the assembly root requirements.txt,
      * installs everything into the venv, then runs pip freeze
      * to produce a fully pinned lock file. Adds it to the git index.
      *
      * Params:
      *     with_odoo_requirements = if set, include Odoo's requirements.txt
      *         in the resolved dependency set
      **/
    void generateRequirementsLock(in bool with_odoo_requirements=false) {
        PyRequirements reqs;

        if (_assembly.path.join("requirements.txt").exists)
            reqs.addRequirementsFile(_assembly.path.join("requirements.txt"));

        auto addon_reqs = _project.addons.collectPyRequirements(
            dist_dir, true, true, true);
        reqs.add(addon_reqs);

        if (with_odoo_requirements
                && _project.odoo.path.join("requirements.txt").exists) {
            reqs.addRequirementsFile(
                _project.odoo.path.join("requirements.txt"));
        }

        if (!reqs.empty)
            _project.venv.installBatchPyRequirements(reqs);

        // Freeze current venv state to lock file
        auto freeze_result = _project.venv.pip("freeze");
        auto lock_path = _assembly.path.join(ASSEMBLY_REQUIREMENTS_LOCK);
        lock_path.writeFile(freeze_result.output);
        repo.add(lock_path);
        infof("Assembly: Generated %s", ASSEMBLY_REQUIREMENTS_LOCK);
    }

    // --- factories: build the base Assembly with the project's serie/cache ---

    static ProjectAssembly initialize(Project project, in Path path) {
        return new ProjectAssembly(
            project,
            Assembly.initialize(
                path, project.odoo.serie,
                new AssemblySourceProviderCached(project.directories.cache.join("assembly"))));
    }

    /// ditto
    static ProjectAssembly initialize(Project project, in Path path, in GitURL git_url) {
        return new ProjectAssembly(
            project,
            Assembly.initialize(
                path, project.odoo.serie,
                new AssemblySourceProviderCached(project.directories.cache.join("assembly")), git_url));
    }

    static ProjectAssembly maybeLoad(Project project, in Path path) {
        auto base = Assembly.maybeLoad(
            path, project.odoo.serie,
            new AssemblySourceProviderCached(project.directories.cache.join("assembly")));
        return base is null ? null : new ProjectAssembly(project, base);
    }

    static ProjectAssembly load(Project project, in Path path) {
        return new ProjectAssembly(
            project,
            Assembly.load(
                path, project.odoo.serie,
                new AssemblySourceProviderCached(project.directories.cache.join("assembly"))));
    }
}
