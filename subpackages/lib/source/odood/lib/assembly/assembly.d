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
private import std.process: environment;
private import std.parallelism: taskPool;

private import dyaml;
private import darkarchive: DarkArchiveReader, DarkArchiveFormat;
private import thepath: Path, createTempPath;
private import darktemple: renderFile;
private import versioned: Version, VersionPart;

private import odood.lib.assembly.exception:
    OdoodAssemblyException,
    OdoodAssemblyNothingToCommitException;
private import odood.lib.assembly.spec;
private import odood.git: GitURL, gitClone, GitRepository, GIT_REF_WORKTREE, isGitRepo, gitListRemoteTags;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.addons.addon;
private import odood.utils: download;
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
    private Path _cache_dir;       // assembly cache directory
    private AddonRepository _repo = null;

    this(in Path path, AssemblySpec spec, in OdooSerie serie, in Path cache_dir) {
        _serie = serie;
        _cache_dir = cache_dir;
        _spec = spec;
        _path = path;
    }

    this(in Path path, in Node yaml_data, in OdooSerie serie, in Path cache_dir) {
        _serie = serie;
        _cache_dir = cache_dir;
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

    /// Cache directory
    @property cache_dir() const => _cache_dir;

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
    static Assembly maybeLoad(in Path path, in OdooSerie serie, in Path cache_dir) {
        if (path.exists && path.isFile) {
            dyaml.Node assembly_spec = dyaml.Loader.fromFile(path.toString()).load();
            return new Assembly(path.parent, assembly_spec, serie, cache_dir);
        } else if (path.exists && path.isDir && path.join("odood-assembly.yml").exists) {
            auto load_path = path.join("odood-assembly.yml");
            Node assembly_spec = dyaml.Loader.fromFile(load_path.toString()).load();
            return new Assembly(path, assembly_spec, serie, cache_dir);
        }
        return null;
    }

    /** Load assembly spec from specified path
      **/
    static Assembly load(in Path path, in OdooSerie serie, in Path cache_dir) {
        auto assembly = maybeLoad(path, serie, cache_dir);
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
    static Assembly initialize(in Path path, in OdooSerie serie, in Path cache_dir) {
        infof("Initializing Odood Assembly at %s ...", path);
        Assembly assembly = new Assembly(path, AssemblySpec.init, serie, cache_dir);
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
    static Assembly initialize(in Path path, in OdooSerie serie, in Path cache_dir, in GitURL git_url) {
        auto repo = gitClone(
                repo: git_url,
                dest: path,
                branch: serie.toString,  // Assembly repo must conform branch naming standards
        );
        enforce!OdoodAssemblyException(
            repo.path.join("odood-assembly.yml").exists,
            "Cannot find assembly config in this repo (%s)".format(git_url.toString));
        return load(repo.path, serie, cache_dir);
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
                    immutable is_tag = OdooStdVersion(source.git_ref).isStandard;
                    if (is_tag)
                        repo.fetchTag(source.git_ref);
                    else
                        repo.fetchOrigin(source.git_ref);

                    if (source.git_commit) {
                        repo.switchBranchTo(source.git_commit);
                        repo.ensureAtCommit(source.git_commit);
                    } else if (is_tag) {
                        repo.switchBranchTo(source.git_ref);
                    } else {
                        repo.switchBranchTo("origin/%s".format(source.git_ref));
                    }
                } else {
                    repo.pull;
                }
            } else {
                // git clone -b accepts both branch names and tag names.
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
                addon_name, serie, addon_name),
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
        cache_dir.mkdir(true);  // ensure cache dir exists
        syncSources();
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
                    getSourceExtraEnv(source))
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
