module odood.lib.assembly.assembly;

/** This module contains utilities to manage assemblies.
  **/

private import std.exception: enforce;
private import std.format: format;
private import std.logger: infof, errorf, warningf, tracef;
private import std.typecons: Nullable, nullable, tuple;
private import std.array: empty, join, array, split, assocArray;
private import std.algorithm: map, canFind, uniq, startsWith;
private import std.range: chain;
private import std.regex: replaceFirst, regex;
private import std.string: strip;
private import std.process: environment;
private import std.datetime.date: DateTime;
private import std.datetime.systime: Clock;
private import std.parallelism: taskPool;

private import dyaml;
private import darkarchive: DarkArchiveReader, DarkArchiveFormat;
private import thepath: Path, createTempPath;
private import darktemple: renderFile;
private import versioned: Version;

private import odood.lib.assembly.exception:
    OdoodAssemblyException,
    OdoodAssemblyNothingToCommitException;
private import odood.lib.assembly.spec;
private import odood.lib.project: Project;
private import odood.git: GitURL, gitClone, GitRepository, isGitRepo;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.addons.addon;
private import odood.utils: download;
private import odood.lib.venv: PyRequirements;
private import odood.lib.addons.manager:
    DEFAULT_INSTALL_PY_REQUIREMENTS,
    DEFAULT_INSTALL_MANIFEST_REQUIREMENTS;
private import odood.lib.addons.repository: AddonRepository;
private import odood.lib.assembly.changes: AssemblyChanges;

public import odood.lib.assembly.spec: AssemblySpec, AssemblySpecSource, AssemblySpecAddon;

// Path to version file in assembly repo
package(odood) immutable ASSEMBLY_VERSION_PATH = Path("VERSION");

// Path to requirements lock file in assembly repo
package(odood) immutable ASSEMBLY_REQUIREMENTS_LOCK = Path("requirements.lock.txt");


class Assembly {
    private AssemblySpec _spec;
    private Path _path;  // assembly root directory
    private Project _project;
    private AddonRepository _repo = null;

    this(Project project, in Path path, AssemblySpec spec) {
        _project = project;
        _spec = spec;
        _path = path;
    }

    this(Project project, in Path path, in Node yaml_data) {
        _project = project;
        _path = path;
        _spec = AssemblySpec(yaml_data);
    }

    /// Spec for this assembly
    @property spec() const => _spec;

    /// Path where configuration is located
    @property path() const => _path;

    /// Odoo serie for this assembly
    @property serie() const => _project.odoo.serie;

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
    static Assembly maybeLoad(Project project, in Path path) {
        if (path.exists && path.isFile) {
            dyaml.Node assembly_spec = dyaml.Loader.fromFile(path.toString()).load();
            return new Assembly(project, path.parent, assembly_spec);
        } else if (path.exists && path.isDir && path.join("odood-assembly.yml").exists) {
            auto load_path = path.join("odood-assembly.yml");
            Node assembly_spec = dyaml.Loader.fromFile(load_path.toString()).load();
            return new Assembly(project, path, assembly_spec);
        }
        return null;
    }

    /** Load assembly spec from specified path
      **/
    static Assembly load(Project project, in Path path) {
        auto assembly = maybeLoad(project, path);
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
    static Assembly initialize(Project project, in Path path) {
        infof("Initializing Odood Assembly at %s ...", path);
        Assembly assembly = new Assembly(project, path, AssemblySpec.init);
        assembly.save();

        infof("Initializing git repository for Odood Assembly at %s ...", path);
        assembly.path.join(".gitignore").writeFile(
            renderFile!("templates/assembly/gitignore.tmpl", assembly));
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
        cache_dir.join("sources").mkdir(true);
        return cache_dir.join("sources", source.hashString);
    }
    private Path getSourceCachePath(in Nullable!AssemblySpecSource source) const {
        return getSourceCachePath(source.get);
    }

    /** Get cache path for addon
      **/
    private Path getAddonCachePath(in string addon_name) const {
        cache_dir.join("addons").mkdir(true);
        return cache_dir.join("addons", addon_name);
    }

    /// ditto
    private Path getAddonCachePath(in AssemblySpecAddon addon) const {
        return getAddonCachePath(addon.name);
    }

    /// ditto
    private Path getAddonCachePath(in Nullable!AssemblySpecAddon addon) const {
        return getAddonCachePath(addon.get);
    }

    private auto getSourceExtraEnv(in AssemblySpecSource source) const {
        string[string] result;

        // Try to find creds in environment
        string[] creds;
        if (!source.name.empty && "ODOOD_ASSEMBLY_%s_CRED".format(source.name) in environment)
            creds = environment["ODOOD_ASSEMBLY_%s_CRED".format(source.name)].split(":");
        else if (!source.access_group.empty && "ODOOD_ASSEMBLY_%s_CRED".format(source.access_group) in environment)
            creds = environment["ODOOD_ASSEMBLY_%s_CRED".format(source.access_group)].split(":");

        if (creds.length > 0) {
            enforce!OdoodAssemblyException(
                creds.length == 2,
                "Cannot parse creds from environment for %s".format(source.name.empty ? source.access_group : source.name));
            enforce!OdoodAssemblyException(
                "GIT_CONFIG_COUNT" !in environment,
                "Assembly source creds via environment not supported, when GIT_CONFIG_COUNT is present in environment.");
            enforce!OdoodAssemblyException(
                source.git_url.scheme == "https",
                "Assembly source creds via environment not supported for non-https sources.");
            string user = creds[0];
            string pass = creds[1];
            result["ODOOD__INT__ASSEMBLY_SOURCE_PASS"] = pass;
            result["GIT_CONFIG_COUNT"] = "2";
            result["GIT_CONFIG_KEY_0"] = "credential.username";
            result["GIT_CONFIG_VALUE_0"] = user;
            result["GIT_CONFIG_KEY_1"] = "credential.helper";
            result["GIT_CONFIG_VALUE_1"] = "!f() { test \"$1\" = get && echo \"password=${ODOOD__INT__ASSEMBLY_SOURCE_PASS}\"; }; f";
        }
        return result;
    }

    /** Sync sources for assembly
      *
      * This method will clone sources related to this assembly to the cache
      **/
    package(odood) void syncSources() const {
        infof("Assembly: syncing sources...");
        // TODO: add timing to understand time consumed by sync of specific repo
        foreach(source; taskPool.parallel(_spec.sources)) {
            infof("Assembly: syncing source %s ...", source);
            auto repo_path = getSourceCachePath(source);
            if (repo_path.exists && !repo_path.isGitRepo)
                repo_path.remove();
            if (repo_path.exists) {
                auto repo = new GitRepository(repo_path, env: getSourceExtraEnv(source));
                if (source.git_ref) {
                    repo.fetchOrigin(source.git_ref);
                    if (source.git_commit) {
                        repo.switchBranchTo(source.git_commit);
                        repo.ensureAtCommit(source.git_commit);
                    } else {
                        repo.switchBranchTo("origin/%s".format(source.git_ref));
                    }
                } else {
                    repo.pull;
                }
            } else {
                auto repo = gitClone(
                    repo: source.git_url,
                    dest: repo_path,
                    branch: source.git_ref ? source.git_ref : serie.toString,
                    single_branch: true,
                    env: getSourceExtraEnv(source));
                if (source.git_commit) {
                    repo.switchBranchTo(source.git_commit);
                    repo.ensureAtCommit(source.git_commit);
                }
            }
            infof("Assembly: source %s synced.", source);
        }
        infof("Assembly: all sources synced.");
    }

    package(odood) auto ensureOdooAppsAddonDownloaded(in string addon_name) {
        auto cache_path = getAddonCachePath(addon_name);
        if (cache_path.exists)
            return cache_path;

        auto temp_dir = createTempPath();
        scope(exit) temp_dir.remove();

        auto download_path = temp_dir.join("%s.zip".format(addon_name));
        infof("Downloading addon %s from odoo apps...", addon_name);
        download(
            "https://apps.odoo.com/loempia/download/%s/%s/%s.zip?deps".format(
                addon_name, _project.odoo.serie, addon_name),
            download_path);
        infof("Unpacking addon %s from odoo apps...", addon_name);
        DarkArchiveReader!(DarkArchiveFormat.zip)(download_path.toAbsolute).extractTo(temp_dir.join("apps"));


        enforce!OdoodAssemblyException(
            isOdooAddon(temp_dir.join("apps", addon_name)),
            "Downloaded archive does not contain requested odoo app!");

        foreach(addon; findAddons(temp_dir.join("apps"))) {
            auto addon_cache_path = getAddonCachePath(addon.name);
            if (!addon_cache_path.exists)
                addon.path.copyTo(addon_cache_path);
        }

        enforce!OdoodAssemblyException(
            cache_path.exists,
            "Addon %s download failed!".format(addon_name));
        return cache_path;
    }

    /** Scan sources for available addons.
      * This method will return mapping with source[hashString][addon.name] -> addon
      **/
    package(odood) auto scanSources() const {
        OdooAddon[string][string] res;
        foreach(source; spec.sources) {
            auto source_path = getSourceCachePath(source);
            res[source.hashString] = _project.addons.scan(path: source_path, recursive: true).map!((a) => tuple(a.name, a)).assocArray;
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
                auto addon_path = ensureOdooAppsAddonDownloaded(addon.name);
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

    void validateAddonsDependencies() const {
        auto assembly_addons = findAddons(dist_dir);
        auto available_addons = _project.addons.getSystemAddonsList()
            .map!((a) => a.name)
            .chain(assembly_addons.map!((a) => a.name))
            .chain(spec.known_addons)
            .uniq.array;

        foreach(addon; assembly_addons)
            foreach(dep; addon.manifest.dependencies)
                enforce!OdoodAssemblyException(
                    available_addons.canFind(dep),
                    "Cannot find dependency %s for addon %s!".format(dep, addon));
    }

    /** Get info about changes between current version and series version
      *
      * Params:
      *    base_rev = base revision. Changes will be generated for changes between base_rev and current commit.
      **/
    auto getChanges(in string base_rev) {
        auto assembly_version = OdooStdVersion(project.odoo.serie, 0);  // Default version.

        if (repo.isFileExists(ASSEMBLY_VERSION_PATH, rev: base_rev))
            // If assembly uses version, then we have to update assembly version from serie branch,
            // and it will be automatically updated after change analysis completed.
            assembly_version = OdooStdVersion(repo.getContent(ASSEMBLY_VERSION_PATH, rev: base_rev))
                .withSerie(project.odoo.serie);

        AssemblyChanges changes = new AssemblyChanges(assembly_version);

        /** Get name of addon, based on path
          *
          **/
        Nullable!string getAddonName(in Path path) {
            Path ipath = path;
            if (ipath.baseName == "__manifest__")
                return ipath.parent.baseName.nullable;

            while(ipath.parent(false).toString != ".") {
                ipath = ipath.parent(false);

                if (repo.isFileExists(ipath.join("__manifest__.py")))
                    return ipath.baseName.nullable;

                if (repo.isFileExists(ipath.join("__manifest__.py"), rev: base_rev))
                    return ipath.baseName.nullable;
            }
            return Nullable!string.init;
        }

        // Here we expect, that all addons are placed in `dist` folder inside assembly,
        // thus, we expect following file structure `dist/my_addon/__manifest__.py` to detect module name.
        string[] addon_names;
        foreach(addon_path; repo.getChangedFiles(start_rev: base_rev)) {
            auto addon_name = getAddonName(addon_path);
            if (addon_name.isNull)
                // Skip things that are not related to addons.
                continue;

            if (!addon_names.canFind(addon_name.get))
                addon_names ~= addon_name.get;
        }

        // Iterate over changed addons, and determine changes for changelog
        foreach(addon_name; addon_names) {
            auto addon_path = dist_dir.join(addon_name);
            auto manifest_path = addon_path.join("__manifest__.py");
            if (repo.isFileExists(manifest_path, rev: base_rev)
                   && !repo.isFileExists(manifest_path))
                // When addon was removed, then we track only its name,
                // because there is no addon in directory.
                changes.logAddonRemoved(addon_name);
            else if (!repo.isFileExists(manifest_path, rev: base_rev)
                   && repo.isFileExists(manifest_path)) {
                // Addon exists in current version, thus we can work with it as with normal addon
                auto addon = new OdooAddon(addon_path);
                auto version_new = addon.manifest.module_version;
                changes.logAddonAdded(
                    addon_name,
                    version_new,
                );
            } else {
                auto addon = new OdooAddon(addon_path);
                auto version_old = repo.getAddonVersion(addon, rev: base_rev).get;
                auto version_new = addon.manifest.module_version;
                auto changelog = addon.readChangelogEntries(
                    start_ver: cast(Nullable!Version)version_old.semver.nullable,
                );
                changes.logAddonUpdated(
                    addon_name,
                    version_old,
                    version_new,
                    changelog,
                );
            }
        }
        changes.postProcess();
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
        auto release_date = cast(DateTime)Clock.currTime();
        auto new_changes_description = renderFile!("templates/assembly/changelog.md.tmpl", changes, release_date);

        // Write latest changelog
        changelog_latest_path.writeFile(new_changes_description);
        repo.add(changelog_latest_path);

        // Update main changelog. At first, we have to switch CHANGELOG.md
        // to original version from series branch
        if (repo.isFileExists(changelog_path, base_rev))
            repo.checkoutFile(base_rev, true, changelog_path);
        else
            repo.remove(changelog_path, force: true, ignore_unmatch: true);

        if (changelog_path.exists) {
            string changelog_content = changelog_path
                .readFileText
                .replaceFirst(regex("# Changelog\n"), new_changes_description);
            changelog_path.writeFile(changelog_content);
        } else
            changelog_path.writeFile(new_changes_description);

        repo.add(changelog_path);

        // Update assembly version
        version_path.writeFile(changes.assembly_version.toString ~ "\n");
        repo.add(version_path);

        infof("Assembly: Changelog generated");
    }

    void generateChangelog() {
        if (repo.hasRemoteUrl("origin"))
            generateChangelog("origin/" ~ project.odoo.serie.toString);
        else if (repo.hasLocalBranch(project.odoo.serie.toString))
            generateChangelog(project.odoo.serie.toString);
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
    void sync(in bool generate_lock=false, in bool with_odoo_requirements=false) {
        spec.validate;
        if (repo.hasRemoteUrl("origin"))
            // Fetch origin/serie branch if origin repo is configured
            repo.fetchOrigin(project.odoo.serie.toString());
        dist_dir.mkdir(true);  // ensure dist dir exists
        cache_dir.mkdir(true);  // ensure cache dir exists
        syncSources();
        syncAddons();
        validateAddonsDependencies();

        if (generate_lock)
            generateRequirementsLock(with_odoo_requirements);
    }

    /** Link assembly addons.
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

        auto lock_path = _path.join(ASSEMBLY_REQUIREMENTS_LOCK);
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
            if (py_requirements && _path.join("requirements.txt").exists) {
                reqs.addRequirementsFile(_path.join("requirements.txt"));
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

        if (_path.join("requirements.txt").exists)
            reqs.addRequirementsFile(_path.join("requirements.txt"));

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
        auto lock_path = _path.join(ASSEMBLY_REQUIREMENTS_LOCK);
        lock_path.writeFile(freeze_result.output);
        repo.add(lock_path);
        infof("Assembly: Generated %s", ASSEMBLY_REQUIREMENTS_LOCK);
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

}
