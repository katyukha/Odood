module odood.lib.assembly;

/** This module containes utilities to manage assemblies.
  **/

private import std.exception: enforce;
private import std.format: format;
private import std.logger: infof, errorf;
private import std.typecons: Nullable, nullable;
private import std.array: empty, join;

private import dyaml;

private import thepath: Path;

private import odood.lib.assembly.exception: OdoodAssemblyException;
private import odood.lib.assembly.spec;
private import odood.lib.project: Project;
private import odood.git: GitURL, gitClone, GitRepository, isGitRepo;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.addons.addon;
private import odood.lib.addons.manager:
    DEFAULT_INSTALL_PY_REQUREMENTS,
    DEFAULT_INSTALL_MANIFEST_REQUREMENTS;

public import odood.lib.assembly.spec: AssemblySpec;


struct Assembly {
    private AssemblySpec _spec;
    private Path _path;  // assembly root directory
    private OdooSerie _serie;
    private Project _project;
    private GitRepository _repo = null;

    this(Project project, in Path path, in OdooSerie serie, AssemblySpec spec) {
        _project = project;
        _spec = spec;
        _path = path;
        _serie = serie;
    }

    this(Project project, in Path path, in Node yaml_data) {
        _project = project;
        _path = path;
        _serie = yaml_data["serie"].as!string;
        _spec = AssemblySpec(yaml_data["spec"]);
    }

    /// Spec for this assembly
    @property spec() const => _spec;

    /// Path where configuration is located
    @property path() const => _path;

    /// Odoo serie for this assembly
    @property serie() const => _serie;

    /// Compute spec path
    @property spec_path() const => _path.join("odood-assembly.yml");

    /// Dist path (where assembly addons located)
    @property dist_dir() const => _path.join("dist");

    /// Cache directory
    @property cache_dir() const => _project.directories.cache.join("assembly");

    /// Project this assembly is related to
    @property project() const => _project;

    /// Git repository instance for this assembly
    @property repo() {
        if (!_repo) {
            enforce!OdoodAssemblyException(
                isGitRepo(_path),
                "This assembly does not have initialized git repo!");
            _repo = new GitRepository(_path);
        }
        return _repo;
    }

    /** Initialize git repository for this assembly
      **/
    private void initializeRepo() {
        _repo = GitRepository.initialize(_path);
    }

    /** Try to load asembly spec from specified location
      **/
    static auto maybeLoad(Project project, in Path path) {
        if (path.exists && path.isFile) {
            dyaml.Node assembly_spec = dyaml.Loader.fromFile(path.toString()).load();
            return Assembly(project, path.parent, assembly_spec).nullable;
        } else if (path.exists && path.isDir && path.join("odood-assembly.yml").exists) {
            auto load_path = path.join("odood-assembly.yml");
            Node assembly_spec = dyaml.Loader.fromFile(load_path.toString()).load();
            return Assembly(project, path, assembly_spec).nullable;
        }
        return Nullable!Assembly.init;
    }

    /** Load assembly spec from specified path
      **/
    static auto load(Project project, in Path path) {
        auto assembly = maybeLoad(project, path);
        enforce!OdoodAssemblyException(
            !assembly.isNull,
            "Cannot find and load Odood Assembly config at %s!".format(path));
        return assembly.get();
    }

    /** Generate YAML configuration for this  assembly
      **/
    auto toYAML() const {
        return dyaml.Node([
            "serie": dyaml.Node(_serie.toString),
            "spec": dyaml.Node(_spec.toYAML),
        ]);
    }

    /** Save any changes to assembly spec
      **/
    void save() const {
        auto dumper = dyaml.dumper.dumper();
        dumper.defaultCollectionStyle = dyaml.style.CollectionStyle.block;

        auto out_file = spec_path.openFile("w");
        scope (exit) out_file.close();

        infof("Saving Odood Assembly config at %s ...", _path);
        dumper.dump(out_file.lockingTextWriter, toYAML);
        infof("Odood Assembly config saved at %s", _path);
    }

    /** Initialize new assembly
      **/
    static Assembly initialize(Project project, in Path path) {
        infof("Initializing Odood Assembly at %s ...", path);
        // TODO: Remover serie from signature, it is present in project
        Assembly assembly = Assembly(project, path, project.odoo.serie, AssemblySpec.init);
        assembly.save();

        infof("Initializing git repository for Odood Assembly at %s ...", path);
        assembly.path.join(".gitignore").writeFile("
*.py[cow]
*.sw[pno]
*.idea/
*~
.ropeproject/
.coverage
htmlcov
");
        assembly.initializeRepo();
        assembly.repo.switchBranchTo(
            branch_name: assembly.serie.toString,
            create: true);
        assembly.repo.add(assembly.path.join(".gitignore"));
        assembly.repo.add(assembly.spec_path);
        assembly.repo.commit("Assembly initialized");
        infof("Odood Assembly at %s initialized  successfully", path);
        return assembly;
    }

    /// ditto
    static Assembly initialize(Project project, in Path path, in GitURL git_url) {
        auto repo = gitClone(
                repo: git_url,
                dest: path,
                branch: project.odoo.serie.toString,  // Assembly repo must conform branch naming standards
        );
        enforce!OdoodAssemblyException(
            repo.path.join("odood-assembly.yml").exists,
            "Cannot find assembly config in this repo (%s)".format(git_url.toString));
        return load(project, repo.path);
    }

    private Path getSourceCachePath(in AssemblySpecSource source) const {
        return cache_dir.join(source.hashString);
    }
    private Path getSourceCachePath(in Nullable!AssemblySpecSource source) const {
        return getSourceCachePath(source.get);
    }

    /** Sync sources for assembly
      *
      * This method will clone sources related to this assembly to the cache
      **/
    package(odood) void syncSources() const {
        infof("Assembly: syncing sources...");
        foreach(source; _spec.sources) {
            infof("Assembly: syncing source %s ...", source);
            auto repo_path = getSourceCachePath(source);
            if (repo_path.exists && !repo_path.isGitRepo)
                repo_path.remove();
            if (repo_path.exists) {
                auto repo = new GitRepository(repo_path);
                if (source.git_ref) {
                    repo.fetchOrigin(source.git_ref);
                    repo.switchBranchTo("origin/%s".format(source.git_ref));
                } else {
                    repo.pull;
                }
            } else {
                gitClone(
                    repo: source.git_url,
                    dest: repo_path,
                    branch: source.git_ref ? source.git_ref : _serie.toString,
                    single_branch: true);
            }
            infof("Assembly: source %s synced.", source);
        }
        infof("Assembly: all sources synced.");
    }

    /** Sync addons for assembly
      *
      * This method will copy addons from assembly
      **/
    package(odood) void syncAddons() {
        // Cleanup old addons
        infof("Assembly: Clenaning addons before syncing...");
        foreach(p; dist_dir.walk) {
            repo.remove(
                path: p,
                recursive: true,
                force: true,
                ignore_unmatch: true,
            );
            // path still exists (for example it was not in git index,
            // remove it to ensure clean state.
            if (p.exists)
                p.remove();
        }
        infof("Assembly: addons cleanded successfully.");

        // Copy new addons
        infof("Assembly: Syncing addons...");
        string[] missing_addon_names = [];
        foreach(addon; spec.addons) {
            infof("Assembly: Syncing addon %s ...", addon);
            enforce!OdoodAssemblyException(
                !addon.from_odoo_apps,
                "odoo_apps source for assembly not supported yet!");
            if (addon.source_name) {
                auto source = spec.getSource(addon.source_name);
                enforce!OdoodAssemblyException(
                    !source.isNull,
                    "Cannot find source %s for addon %s!".format(source, addon));

                auto source_path = getSourceCachePath(source);
                bool addon_found = false;
                foreach(s_addon; _project.addons.scan(source_path)) {
                    if (s_addon.name == addon.name) {
                        s_addon.path.copyTo(dist_dir.join(addon.name));
                        repo.add(dist_dir.join(addon.name));
                        addon_found = true;
                        break;
                    }
                }
                if (!addon_found) {
                    errorf("Assembly: Cannot find addon %s!", addon);
                    missing_addon_names ~= addon.name;
                }
            } else {
                foreach(source; spec.sources) {
                    auto source_path = getSourceCachePath(source);
                    bool addon_found = false;
                    foreach(s_addon; _project.addons.scan(source_path)) {
                        if (s_addon.name == addon.name) {
                            s_addon.path.copyTo(dist_dir.join(addon.name));
                            repo.add(dist_dir.join(addon.name));
                            addon_found = true;
                            break;
                        }
                    }
                    if (!addon_found) {
                        errorf("Assembly: Cannot find addon %s!", addon);
                        missing_addon_names ~= addon.name;
                    }
                }
            }
            infof("Assembly: Addon %s synced.", addon);
        }
        enforce!OdoodAssemblyException(
            missing_addon_names.empty,
            "Cannot find addons:\n%s".format(missing_addon_names.join("\n")));
        infof("Assembly: All addons synced.");
    }

    /** Synchronize assembly (sources and addons)
      *
      * Update assembly addons from recent versiones from specified git sources
      **/
    void sync() {
        dist_dir.mkdir(true);  // ensure dist dir exists
        cache_dir.mkdir(true);  // ensure cache dir exists
        syncSources();
        syncAddons();
    }

    /** Link assembly addons.
      *
      * Remove symlinks that point to this assembly from custom addons,
      * and create only valid symlinks.
      **/
    void link(
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUREMENTS) const {
        // Remove all links in custom addons that point to this assembly
        foreach(p; _project.directories.addons.walk) {
            if (p.isSymlink && p.readLink.isInside(dist_dir))
                p.remove();
        }
        _project.addons.link(
            search_path: dist_dir,
            recursive: true,
            force: true,);
    }

    void pull() {
        repo.pull();
    }
}
