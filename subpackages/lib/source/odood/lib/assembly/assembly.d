module odood.lib.assembly.assembly;

/** This module contains utilities to manage assemblies.
  **/

private import std.exception: enforce;
private import std.format: format;
private import std.logger: infof, errorf, warningf, tracef;
private import std.typecons: Nullable, nullable;
private import std.array: empty, join, array, split;
private import std.algorithm: map, canFind, uniq;
private import std.range: chain;
private import std.regex: replaceFirst, regex;
private import std.process: environment;
private import std.datetime.date: DateTime;
private import std.datetime.systime: Clock;

private import dyaml;
private import thepath: Path;
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
private import odood.lib.addons.manager:
    DEFAULT_INSTALL_PY_REQUREMENTS,
    DEFAULT_INSTALL_MANIFEST_REQUREMENTS;
private import odood.lib.addons.repository: AddonRepository;
private import odood.lib.assembly.changes: AssemblyChanges;

public import odood.lib.assembly.spec: AssemblySpec;

// Path to version file in assembly repo
package(odood) immutable ASSEMBLY_VERSION_PATH = Path("VERSION");


struct Assembly {
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
    @property dist_dir() const => _path.join("dist");

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
        Assembly assembly = Assembly(project, path, AssemblySpec.init);
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
        return cache_dir.join(source.hashString);
    }
    private Path getSourceCachePath(in Nullable!AssemblySpecSource source) const {
        return getSourceCachePath(source.get);
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
        // TODO: make it parallel and depth=1
        // TODO: add timing to understand time consumed by sync of specific repo
        foreach(source; _spec.sources) {
            infof("Assembly: syncing source %s ...", source);
            auto repo_path = getSourceCachePath(source);
            if (repo_path.exists && !repo_path.isGitRepo)
                repo_path.remove();
            if (repo_path.exists) {
                auto repo = new GitRepository(repo_path, env: getSourceExtraEnv(source));
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
                    branch: source.git_ref ? source.git_ref : serie.toString,
                    single_branch: true,
                    env: getSourceExtraEnv(source));
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
        // TODO: try to make it parallel
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
                tracef("Searching for addon %s inside %s", addon.name, source);
                foreach(s_addon; _project.addons.scan(path: source_path, recursive: true)) {
                    if (s_addon.name == addon.name) {
                        s_addon.path.copyTo(dist_dir.join(addon.name));
                        repo.add(dist_dir.join(addon.name));
                        addon_found = true;
                        tracef("Addon %s from %s source added.", addon.name, source);
                        break;
                    }
                }
                if (addon_found) {
                    infof("Assembly: Addon %s synced.", addon);
                } else {
                    errorf("Assembly: Cannot find addon %s!", addon);
                    missing_addon_names ~= addon.name;
                }
            } else {
                bool addon_found = false;
                foreach(source; spec.sources) {
                    if (source.no_search)
                        // Skip source, that should not be used to search for addons.
                        continue;

                    auto source_path = getSourceCachePath(source);
                    tracef("Searching for addon %s inside %s", addon.name, source);
                    foreach(s_addon; _project.addons.scan(path: source_path, recursive: true)) {
                        if (s_addon.name == addon.name) {
                            s_addon.path.copyTo(dist_dir.join(addon.name));
                            repo.add(dist_dir.join(addon.name));
                            addon_found = true;
                            tracef("Addon %s from %s source added.", addon.name, source);
                            break;
                        }
                    }
                    if (addon_found)
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

        // Here we expect, that all addons are placed in `dist` folder inside assembly,
        // thus, we expect following file structure `dist/my_addon/__manifest__.py` to detect module name.
        string[] addon_names;
        foreach(addon_path; repo.getChangedFiles(start_rev: base_rev, path_filters: ["dist/*"])) {
            auto apath_segments = addon_path.segments;
            if (apath_segments.front != "dist")
                // Skip things that are not related to addons.
                continue;
            apath_segments.popFront;
            auto addon_name = apath_segments.front;
            if (!addon_names.canFind(addon_name))
                addon_names ~= addon_name;
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
        infof("Assembly: Generiating changelog.");
        // TODO: We have also handle cases, when no origin repo connected to assembly

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
        // Base, that have to be used to generate changelog
        auto base_rev = "origin/"~project.odoo.serie.toString;
        generateChangelog(base_rev);
    }

    /** Synchronize assembly (sources and addons)
      *
      * Update assembly addons from recent versiones from specified git sources
      **/
    void sync() {
        if (repo.hasRemoteUrl("origin"))
            // Fetch origin/serie branch if origin repo is configured
            repo.fetchOrigin(project.odoo.serie.toString());
        dist_dir.mkdir(true);  // ensure dist dir exists
        cache_dir.mkdir(true);  // ensure cache dir exists
        syncSources();
        syncAddons();
        validateAddonsDependencies();
    }

    /** Link assembly addons.
      *
      * Remove symlinks that point to this assembly from custom addons,
      * and create only valid symlinks.
      **/
    void link(
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUREMENTS) const {
        infof("Assembly Link: Cleanup old symlinks.");
        if (_path.join("requirements.txt").exists) {
            infof("Installing python requirements from '%s'", _path.join("requirements.txt"));
            _project.venv.installPyRequirements(_path.join("requirements.txt"));
        }
        // Remove all links in custom addons that point to this assembly
        foreach(p; _project.directories.addons.walk) {
            if (p.isSymlink && p.readLink.isInside(dist_dir))
                p.remove();
        }
        infof("Assembly Link: Start linking");
        _project.addons.link(
            search_path: dist_dir,
            recursive: true,
            force: true,
            py_requirements: py_requirements,
            manifest_requirements: manifest_requirements);
        infof("Assembly Link: Completed");
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

