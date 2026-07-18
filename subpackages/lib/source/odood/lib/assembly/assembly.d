module odood.lib.assembly.assembly;

/** This module contains utilities to manage assemblies.
  **/

private import std.exception: enforce;
private import std.format: format;
private import std.logger: infof, errorf, warningf, tracef;
private import std.typecons: Nullable, nullable, tuple;
private import std.array: empty, join, array, split, assocArray;
private import std.algorithm: map, filter, canFind, uniq, startsWith, maxElement;
private import std.range: chain;
private import std.regex: replaceFirst, regex;
private import std.string: strip;

private import dyaml;
private import thepath: Path;
private import darktemple: renderFile;
private import versioned: Version, VersionPart;

private import odood.lib.assembly.exception:
    OdoodAssemblyException,
    OdoodAssemblyNothingToCommitException;
private import odood.lib.assembly.spec;
private import odood.lib.assembly.source_provider: AssemblySourceProviderInterface;
private import odood.lib.assembly.source_env: resolveSourceGitEnv;
private import odood.git: GitURL, gitClone, GitRepository, GIT_REF_WORKTREE, isGitRepo, gitListRemoteTags;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.addons.addon;
private import odood.lib.addons.repository: AddonRepository, PrepareReleaseResult;
private import odood.lib.addons.changes: AddonRepositoryChanges;

public import odood.lib.assembly.spec: AssemblySpec, AssemblySpecSource, AssemblySpecAddon;

/// Result of upgrading a single assembly source ref
struct SourceUpgradeResult {
    string source_name;
    string old_ref;
    string new_ref;
    bool changed;
}

// Path to version file in assembly repo
package(odood) immutable ASSEMBLY_VERSION_PATH = Path("VERSION");

// Path to requirements lock file in assembly repo
package(odood) immutable ASSEMBLY_REQUIREMENTS_LOCK = Path("requirements.lock.txt");


class Assembly {
    private AssemblySpec _spec;
    private Path _path;  // assembly root directory
    private OdooSerie _serie;      // target Odoo serie
    private AssemblySourceProviderInterface _source_provider;  // materializes sources/addons
    private AddonRepository _repo = null;

    this(in Path path, AssemblySpec spec, in OdooSerie serie,
            AssemblySourceProviderInterface source_provider) {
        _serie = serie;
        _source_provider = source_provider;
        _spec = spec;
        _path = path;
    }

    this(in Path path, in Node yaml_data, in OdooSerie serie,
            AssemblySourceProviderInterface source_provider) {
        _serie = serie;
        _source_provider = source_provider;
        _path = path;
        _spec = AssemblySpec(yaml_data);
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
    @property dist_dir() const {
        final switch(_spec.layout) {
            case AssemblyLayout.STANDARD:
                return _path.join("dist");
            case AssemblyLayout.FLAT:
                return _path;
        }
    }

    /// Changelog path
    @property changelog_path() const => _path.join("CHANGELOG.md");

    /// Changelog path
    @property changelog_latest_path() const => _path.join("CHANGELOG.latest.md");

    /// Path to repo version file
    @property version_path() const => _path.join(ASSEMBLY_VERSION_PATH);

    /// Git repository instance for this assembly
    @property repo() {
        if (!_repo) {
            enforce!OdoodAssemblyException(
                isGitRepo(_path),
                "This assembly does not have initialized git repo!");
            _repo = new AddonRepository(_path);
        }
        return _repo;
    }

    /** Initialize git repository for this assembly
      **/
    private void initializeRepo() {
        _repo = new AddonRepository(GitRepository.initialize(_path));
    }

    /** Try to load asembly spec from specified location
      **/
    static Assembly maybeLoad(in Path path, in OdooSerie serie,
            AssemblySourceProviderInterface source_provider) {
        if (path.exists && path.isFile) {
            dyaml.Node assembly_spec = dyaml.Loader.fromFile(path.toString()).load();
            return new Assembly(path.parent, assembly_spec, serie, source_provider);
        } else if (path.exists && path.isDir && path.join("odood-assembly.yml").exists) {
            auto load_path = path.join("odood-assembly.yml");
            Node assembly_spec = dyaml.Loader.fromFile(load_path.toString()).load();
            return new Assembly(path, assembly_spec, serie, source_provider);
        }
        return null;
    }

    /** Load assembly spec from specified path
      **/
    static Assembly load(in Path path, in OdooSerie serie,
            AssemblySourceProviderInterface source_provider) {
        auto assembly = maybeLoad(path, serie, source_provider);
        enforce!OdoodAssemblyException(
            assembly !is null,
            "Cannot find and load Odood Assembly config at %s!".format(path));
        return assembly;
    }

    /** Generate YAML configuration for this  assembly
      **/
    auto toYAML() const {
        return _spec.toYAML;
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
    static Assembly initialize(in Path path, in OdooSerie serie,
            AssemblySourceProviderInterface source_provider) {
        infof("Initializing Odood Assembly at %s ...", path);
        Assembly assembly = new Assembly(path, AssemblySpec.init, serie, source_provider);
        assembly.save();

        infof("Initializing git repository for Odood Assembly at %s ...", path);
        assembly.path.join(".gitignore").writeFile(
            renderFile!("templates/assembly/gitignore.tmpl", assembly));
        assembly.initializeRepo();
        assembly.repo.createBranch(assembly.serie.toString);
        assembly.repo.add(assembly.path.join(".gitignore"));
        assembly.repo.add(assembly.spec_path);
        assembly.repo.commit("Assembly initialized");
        infof("Odood Assembly at %s initialized  successfully", path);
        return assembly;
    }

    /// ditto
    static Assembly initialize(in Path path, in OdooSerie serie,
            AssemblySourceProviderInterface source_provider, in GitURL git_url) {
        auto repo = gitClone(
                repo: git_url,
                dest: path,
                branch: serie.toString,  // Assembly repo must conform branch naming standards
        );
        enforce!OdoodAssemblyException(
            repo.path.join("odood-assembly.yml").exists,
            "Cannot find assembly config in this repo (%s)".format(git_url.toString));
        return load(repo.path, serie, source_provider);
    }

    /** Scan sources for available addons.
      * This method will return mapping with source[hashString][addon.name] -> addon
      **/
    package(odood) auto scanSources() {
        OdooAddon[string][string] res;
        foreach(source; spec.sources) {
            auto source_path = _source_provider.resolveSource(source, serie);
            res[source.hashString] = findAddons(source_path, recursive: true).map!((a) => tuple(a.name, a)).assocArray;
        }
        return res;
    }

    /** Sync addons for assembly
      *
      * This method will copy addons from assembly
      **/
    package(odood) void syncAddons() {
        // Cleanup old addons
        // TODO: try to make it parallel
        infof("Assembly: Clenaning addons before syncing...");
        foreach(p; dist_dir.walk) {
            /* Here we have to remove any directory inside dist folder.
             * Except those ones started with '.'.
             * This is needed to ensure the dist directory is clear before sync.
             */
            if (p.isOdooAddon || (p.isDir && !p.baseName.startsWith("."))) {
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
        }
        infof("Assembly: addons cleanded successfully.");

        // Copy new addons
        infof("Assembly: Syncing addons...");
        const auto sourceScanRes = scanSources();
        string[] missing_addon_names = [];
        foreach(addon; _spec.addons) {
            infof("Assembly: Syncing addon %s ...", addon);
            if (addon.from_odoo_apps) {
                auto addon_path = _source_provider.resolveExternalAddon(addon, serie);
                addon_path.copyTo(dist_dir.join(addon.name));
                repo.add(dist_dir.join(addon.name));
                infof("Assembly: Addon %s synced from Odoo Apps.", addon);
            } else if (addon.source_name) {
                auto source = spec.getSource(addon.source_name);
                enforce!OdoodAssemblyException(
                    !source.isNull,
                    "Cannot find source %s for addon %s!".format(addon.source_name, addon));

                if (addon.name !in sourceScanRes[source.get.hashString]) {
                    errorf("Assembly: Cannot find addon %s!", addon);
                    missing_addon_names ~= addon.name;
                } else {
                    auto s_addon = sourceScanRes[source.get.hashString][addon.name];
                    s_addon.path.copyTo(dist_dir.join(addon.name));
                    repo.add(dist_dir.join(addon.name));
                    infof("Assembly: Addon %s synced.", addon);
                }
            } else {
                bool addon_found = false;
                foreach(source; spec.sources) {
                    if (source.no_search)
                        // Skip source, that should not be used to search for addons.
                        continue;

                    if (addon.name !in sourceScanRes[source.hashString])
                        continue;

                    auto s_addon = sourceScanRes[source.hashString][addon.name];
                    s_addon.path.copyTo(dist_dir.join(addon.name));
                    repo.add(dist_dir.join(addon.name));
                    addon_found = true;
                    break;
                }
                if (addon_found) {
                    infof("Assembly: Addon %s synced.", addon);
                } else {
                    errorf("Assembly: Cannot find addon %s!", addon);
                    missing_addon_names ~= addon.name;
                }
            }
        }
        enforce!OdoodAssemblyException(
            missing_addon_names.empty,
            "Cannot find addons:\n%s".format(missing_addon_names.join("\n")));
        infof("Assembly: All addons synced.");
    }

    /** Validate that every assembly addon's dependencies are satisfiable
      * (by the provided system addons, other assembly addons, or the spec's
      * known-addons list).
      *
      * Project-free: the caller supplies the names of addons the target Odoo
      * instance provides. A `ProjectAssembly` passes the project's system
      * addons; a standalone packager may source that list from a bundled
      * per-serie manifest or an Odoo checkout.
      *
      * Params:
      *    system_addons = names of addons provided by the target Odoo instance
      *        (core plus any always-available addons).
      **/
    void validateAddonsDependencies(in string[] system_addons) const {
        auto assembly_addons = findAddons(dist_dir);
        auto available_addons = chain(
                system_addons,
                assembly_addons.map!((a) => a.name),
                spec.known_addons)
            .uniq.array;

        string[] missing_dependencies;
        foreach(addon; assembly_addons)
            foreach(dep; addon.manifest.dependencies)
                if (!available_addons.canFind(dep))
                    missing_dependencies ~= "%s (required by %s)".format(
                        dep, addon.name);

        enforce!OdoodAssemblyException(
            missing_dependencies.empty,
            "Cannot find following dependencies:\n%s".format(
                missing_dependencies.join("\n")));
    }

    /** Get info about changes between current version and series version
      *
      * Params:
      *    base_rev = base revision. Changes will be generated for changes between base_rev and current commit.
      **/
    auto getChanges(in string base_rev) {
        auto assembly_version = OdooStdVersion(serie, 0);  // Default version.

        if (repo.isFileExists(ASSEMBLY_VERSION_PATH, rev: base_rev))
            assembly_version = OdooStdVersion(
                repo.getContent(ASSEMBLY_VERSION_PATH, rev: base_rev))
                .withSerie(serie);

        auto changes = repo.collectChanges(
            base_rev,
            GIT_REF_WORKTREE,
            ignore_translations: false,
            initial_version: assembly_version);
        // Assemblies have no reserved hotfix segment, so the bump floors to
        // PATCH (releases floor to MINOR to keep PATCH free for hotfixes).
        changes.postProcess(VersionPart.PATCH);
        return changes;
    }

    /** Generate changelog for assembly
      *
      * Params:
      *    base_rev = base revision. Changelog will be generated for changes between base_rev and current commit.
      **/
    void generateChangelog(in string base_rev) {
        infof("Assembly: Generating changelog.");

        auto changes = getChanges(base_rev: base_rev);
        repo.generateChangelog(PrepareReleaseResult(changes.repo_version, changes, base_rev));

        // Assembly-specific: persist the version number in VERSION file.
        version_path.writeFile(changes.repo_version.toString ~ "\n");
        repo.add(version_path);

        infof("Assembly: Changelog generated");
    }

    void generateChangelog() {
        if (repo.hasRemoteUrl("origin"))
            generateChangelog("origin/" ~ serie.toString);
        else if (repo.hasLocalBranch(serie.toString))
            generateChangelog(serie.toString);
        else
            throw new OdoodAssemblyException(
                "Changelog generation requires an 'origin' remote to be configured " ~
                "and local or remote branch named same as Odoo serie. " ~
                "Or, base revision to compare changes to have to be provided.");
    }

    void generateDockerfile() {
        infof("Assembly: Preparing Dockerfile...");
        auto assembly = this;
        // TODO: move to template, after darktemple will be ready for this
        auto handle_requirements_txt = path.join("requirements.txt").exists;
        auto handle_requirements_lock_txt = path.join(ASSEMBLY_REQUIREMENTS_LOCK).exists;
        auto assembly_version = version_path.exists ? version_path.readFileText.strip : "";
        auto assembly_source_url = repo.hasRemoteUrl("origin") ? repo.getRemoteUrl().toString : "";
        if (path.join("Dockerfile").exists) {
            string dockerfile_content = path.join("Dockerfile")
                .readFileText
                .replaceFirst(
                    regex(".*# ---- ODOOD END DYNAMIC DOCKER CONFIG ----\n", "s"),
                    renderFile!("templates/assembly/Dockerfile.tmpl", assembly, handle_requirements_txt, handle_requirements_lock_txt, assembly_version, assembly_source_url));
            path.join("Dockerfile").writeFile(dockerfile_content);
        } else {
            path.join("Dockerfile").writeFile(
                renderFile!("templates/assembly/Dockerfile.tmpl", assembly, handle_requirements_txt, handle_requirements_lock_txt, assembly_version, assembly_source_url));
        }
        repo.add(path.join("Dockerfile"));
        infof("Assembly: Dockerfile generated/updated!");

        if (!path.join(".dockerignore").exists) {
            path.join(".dockerignore").writeFile(renderFile!("templates/assembly/dockerignore.tmpl"));
            repo.add(path.join(".dockerignore"));
            infof("Assembly: Default .dockerignore generated!");
        }
    }

    /** Synchronize assembly (sources and addons)
      *
      * Update assembly addons from recent versiones from specified git sources
      *
      * Params:
      *     generate_lock = if set, generate requirements.lock.txt after syncing
      *     with_odoo_requirements = if set, include Odoo's requirements.txt
      *         when generating lock file
      **/
    /** Fetch sources and assemble addons into `dist_dir`.
      *
      * Project-free packaging step: validates the spec, fetches sources, and
      * populates the dist directory. Dependency validation against a live Odoo
      * instance and requirements-lock generation live in `ProjectAssembly.sync`.
      **/
    void sync() {
        spec.validate;
        if (repo.hasRemoteUrl("origin"))
            // Fetch origin/serie branch if origin repo is configured
            repo.fetchOrigin(serie.toString());
        dist_dir.mkdir(true);  // ensure dist dir exists
        _source_provider.ensureSources(_spec.sources, serie);
        syncAddons();
    }

    void pull() {
        infof("Assembly Pull: Pulling changes for assembly.");
        auto old_commit = repo.getCurrCommit;
        repo.pull();
        auto curr_commit = repo.getCurrCommit;
        if (old_commit == curr_commit)
            infof("Assembly Pull: Completed.");
        else
            infof("Assembly Pull: Completed: %s..%s", old_commit, curr_commit);
    }

    void push(in string branch_name=null) {
        if (branch_name) infof("Assembly Push: Pushing assembly changes to %s.", branch_name);
        else infof("Assembly Push: Pushing assembly changes.");

        repo.push(branch_name: branch_name);
        infof("Assembly Push: Completed.");
    }

    /// Add source to assembly
    void addSource(in GitURL git_url, in string name=null, in string git_ref=null) {
        _spec.addSource(git_url: git_url, name: name,  git_ref: git_ref);
    }

    /// Add addon to assembly
    void addAddon(in string name, in string source_name=null, in bool from_odoo_apps=false) {
        _spec.addAddon(name: name, source_name: source_name,  from_odoo_apps: from_odoo_apps);
    }

    /** For each source, query the remote for tags matching the project's Odoo serie,
      * pick the highest OdooStdVersion tag, and update the source's git_ref in place.
      *
      * The caller must call save() after this to persist spec changes.
      * Returns one SourceUpgradeResult per source.
      **/
    SourceUpgradeResult[] upgradeSourceRefs() {
        immutable serie = _serie;
        SourceUpgradeResult[] results;

        foreach(ref source; _spec.sources) {
            immutable src_name = source.name.empty ? source.git_url.toString : source.name;
            immutable old_ref = source.git_ref;

            if (!OdooStdVersion(old_ref).isStandard) {
                tracef("Assembly: Skipping %s — ref '%s' is not a version tag.", src_name, old_ref);
                continue;
            }

            infof("Assembly: Checking %s for new version tags ...", src_name);
            auto versions = gitListRemoteTags(
                    source.git_url.toString,
                    resolveSourceGitEnv(source))
                .map!(t => OdooStdVersion(t))
                .filter!(v => v.isStandard && v.serie == serie)
                .array;

            if (versions.empty) {
                infof("Assembly: No version tags found for %s.", src_name);
                results ~= SourceUpgradeResult(
                    source_name: src_name,
                    old_ref: old_ref,
                    new_ref: old_ref,
                    changed: false);
                continue;
            }

            immutable newest = versions.maxElement;
            immutable new_ref = newest.toString;

            if (new_ref == old_ref) {
                infof("Assembly: %s is already at latest (%s).", src_name, new_ref);
                results ~= SourceUpgradeResult(
                    source_name: src_name,
                    old_ref: old_ref,
                    new_ref: new_ref,
                    changed: false);
            } else {
                infof("Assembly: Upgrading %s: %s → %s.", src_name, old_ref.empty ? "(none)" : old_ref, new_ref);
                source.git_ref = new_ref;
                source.git_commit = null;
                results ~= SourceUpgradeResult(
                    source_name: src_name,
                    old_ref: old_ref,
                    new_ref: new_ref,
                    changed: true);
            }
        }
        return results;
    }

}


// Assembly.sync() materializes entirely through the injected provider: a fake
// provider serves a local fixture tree, so the flow runs with no network.
unittest {
    import unit_threaded.assertions;
    import thepath: createTempPath;
    import odood.git: GitURL;
    import odood.lib.assembly.source_provider: AssemblySourceProviderInterface;

    auto root = createTempPath;
    scope(exit) root.remove();

    // Fixture "source" tree containing one addon.
    auto src = root.join("fake-source");
    src.join("my_addon").mkdir(true);
    src.join("my_addon", "__init__.py").writeFile("");
    src.join("my_addon", "__manifest__.py").writeFile(
        `{"name": "my_addon", "version": "17.0.1.0.0", "depends": ["base"]}`);

    // Fake provider: serves the fixture tree for any source, never fetches.
    static class FakeProvider : AssemblySourceProviderInterface {
        Path src_path;
        bool ensured = false;
        this(Path p) { src_path = p; }
        override void ensureSources(in AssemblySpecSource[] sources, in OdooSerie serie) {
            ensured = true;
        }
        override Path resolveSource(in AssemblySpecSource source, in OdooSerie serie) {
            return src_path;
        }
        override Path resolveExternalAddon(in AssemblySpecAddon specAddon, in OdooSerie serie) {
            assert(false, "no external addons expected in this test");
        }
    }
    auto provider = new FakeProvider(src);

    auto assembly_path = root.join("assembly");
    assembly_path.mkdir(true);  // initialize() writes the spec before git-init'ing
    auto assembly = Assembly.initialize(assembly_path, OdooSerie("17.0"), provider);
    assembly.addSource(GitURL("https://example.test/repo"));
    assembly.addAddon("my_addon");

    assembly.dist_dir.join("my_addon").exists.shouldBeFalse;
    assembly.sync();

    provider.ensured.shouldBeTrue;                                   // ensureSources was called
    assembly.dist_dir.join("my_addon").exists.shouldBeTrue;         // addon copied into dist
    assembly.dist_dir.join("my_addon", "__manifest__.py").exists.shouldBeTrue;
}
