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
private import std.string: strip, splitLines;

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
private import odood.utils.addons.addon_list:
    addonListRows, renderMarkdownTable, renderCsv;
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

// Paths to generated addon-list files in the assembly repo
package(odood) immutable ASSEMBLY_ADDONS_MD_PATH = Path("ADDONS.md");
package(odood) immutable ASSEMBLY_ADDONS_CSV_PATH = Path("ADDONS.csv");


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

    /** Version of the most recent release.
      *
      * Release tags are authoritative; the `VERSION` file is only consulted
      * for an assembly that has no release tag yet.
      *
      * Params:
      *     include_remote = also consider tags that exist only on the remote.
      *         Costs a `git ls-remote`; pass false where a local answer is
      *         good enough.
      *
      * Returns: null when the assembly has never been released.
      **/
    Nullable!OdooStdVersion currentVersion(in bool include_remote = true) {
        auto latest = repo.getLatestRelease(serie, include_remote);
        if (!latest.isNull)
            return latest;

        if (version_path.exists) {
            auto parsed = OdooStdVersion(version_path.readFileText.strip);
            if (parsed.isStandard)
                return parsed.withSerie(serie).nullable;
        }
        return Nullable!OdooStdVersion.init;
    }

    /** Release tag of this serie pointing at HEAD, if there is one.
      *
      * Identifies a release that was tagged but whose push did not complete:
      * since the next version is measured from the latest tag, such a tag makes
      * the following run see no changes at all.
      *
      * Returns: null when HEAD carries no release tag for this serie.
      **/
    Nullable!OdooStdVersion releasedAtHead() {
        immutable head = repo.getCurrCommit;
        foreach(tag; repo.listLocalTags()) {
            auto ver = OdooStdVersion(tag);
            if (!ver.isStandard || ver.serie != serie)
                continue;
            if (repo.tryRevParse(tag) == head)
                return ver.nullable;
        }
        return Nullable!OdooStdVersion.init;
    }

    /** Revision to compare against when the assembly has no release tag yet.
      *
      * Never the stable branch: by the time a release runs, the content being
      * released is already on it, so that comparison finds nothing and the
      * first release could never happen.
      *
      * With a `VERSION` file, the commit that last wrote it is the previous
      * release point. Without one the assembly has never been released, so the
      * base is the start of history and everything currently in `dist` counts
      * as new.
      **/
    private string defaultBaseRev() {
        /* On a shallow clone the boundary commit looks like a root that
         * introduced every file, so both lookups below would return it and the
         * release would silently find nothing to describe. */
        enforce!OdoodAssemblyException(
            !repo.isShallow,
            "Cannot determine the previous release point in a shallow " ~
            "clone. Fetch the full history (for example 'fetch-depth: 0' " ~
            "on GitHub Actions, or 'GIT_DEPTH: 0' on GitLab CI).");

        if (version_path.exists) {
            immutable last_release = repo.lastCommitFor(ASSEMBLY_VERSION_PATH);
            if (!last_release.empty)
                return last_release;
        }

        immutable root = repo.rootCommit;
        enforce!OdoodAssemblyException(
            !root.empty,
            "Cannot release an assembly with no commits.");
        return root;
    }

    /** Version the next release bumps from, as recorded at `base_rev`.
      *
      * Params:
      *     base_rev = revision to read the `VERSION` file at.
      *     latest = latest release tag. Resolved by the caller, so one release
      *         queries the remote once.
      **/
    private OdooStdVersion resolveBaseVersion(
            in string base_rev, in Nullable!OdooStdVersion latest) {
        Nullable!OdooStdVersion from_file;
        if (repo.isFileExists(ASSEMBLY_VERSION_PATH, rev: base_rev)) {
            auto parsed = OdooStdVersion(
                repo.getContent(ASSEMBLY_VERSION_PATH, rev: base_rev).strip);
            if (parsed.isStandard)
                from_file = parsed.withSerie(serie).nullable;
        }

        if (latest.isNull)
            return from_file.isNull ? OdooStdVersion(serie, 0) : from_file.get;

        /* Both are written by the same release commit, so when base_rev IS the
         * tagged commit a disagreement means a hand edit or a release made
         * outside Odood. The tag wins. At any other base_rev an older value is
         * simply the version of that time — nothing to warn about. */
        if (!from_file.isNull && from_file.get != latest.get
                && repo.tryRevParse(base_rev) == repo.tryRevParse(latest.get.toString))
            warningf(
                "Assembly: VERSION at %s says %s, but the release tag there " ~
                "is %s. Using the tag.", base_rev, from_file.get, latest.get);
        return latest.get;
    }

    /** Get info about changes between `base_rev` and the working tree.
      *
      * Params:
      *    base_rev = base revision. Changes will be generated for changes between base_rev and current commit.
      **/
    auto getChanges(in string base_rev) {
        return getChanges(base_rev, repo.getLatestRelease(serie));
    }

    /// ditto, with the latest release tag already resolved.
    private auto getChanges(
            in string base_rev, in Nullable!OdooStdVersion latest) {
        auto changes = repo.collectChanges(
            base_rev,
            GIT_REF_WORKTREE,
            ignore_translations: false,
            initial_version: resolveBaseVersion(base_rev, latest));
        // Assemblies have no reserved hotfix segment, so the bump floors to
        // PATCH (releases floor to MINOR to keep PATCH free for hotfixes).
        changes.postProcess(VersionPart.PATCH);
        return changes;
    }

    /** Compute the next assembly release.
      *
      * The latest release tag is both the comparison base and the version to
      * bump from. With no tag yet, the base is the commit that last wrote the
      * `VERSION` file (whose value is bumped from), or the start of history
      * for an assembly that has never been released at all.
      *
      * Performs no writes — the caller generates artifacts, commits and tags.
      *
      * Params:
      *     base_rev = explicit base revision, overriding the tag lookup.
      *
      * Returns: null when nothing changed since the base.
      **/
    Nullable!PrepareReleaseResult prepareRelease(in string base_rev = null) {
        auto latest = repo.getLatestRelease(serie);
        immutable start_ref = base_rev.empty
            ? (latest.isNull ? defaultBaseRev() : ensureTagAvailable(latest.get))
            : base_rev;

        auto changes = getChanges(start_ref, latest);
        if (!changes.has_changes)
            return Nullable!PrepareReleaseResult.init;

        return PrepareReleaseResult(
            changes.repo_version, changes, start_ref).nullable;
    }

    /** Make sure `tag` can be used as a local revision, fetching it if needed.
      *
      * The latest release is resolved from local tags merged with the remote
      * listing, so the winner may be a tag this clone does not have — routine
      * on a shallow or `--no-tags` checkout.
      *
      * Returns: the tag name.
      **/
    private string ensureTagAvailable(in OdooStdVersion tag) {
        immutable name = tag.toString;
        if (!repo.tryRevParse(name).empty)
            return name;

        if (repo.hasRemoteUrl("origin")) {
            infof("Assembly: Fetching release tag %s ...", name);
            try {
                repo.fetchTag(name);
            } catch (Exception e) {
                tracef("Assembly: Cannot fetch tag %s: %s", name, e.msg);
            }
        }

        enforce!OdoodAssemblyException(
            !repo.tryRevParse(name).empty,
            ("Release tag %s is not available in this clone, so the changes " ~
             "since it cannot be determined. Fetch the full history and tags " ~
             "(for example 'fetch-depth: 0' on GitHub Actions, or " ~
             "'GIT_DEPTH: 0' on GitLab CI).").format(name));
        return name;
    }

    deprecated("Assign versions with prepareRelease, then call " ~
        "generateChangelog(result) and generateVersionFile(version); " ~
        "this overload couples the three and always writes VERSION.")
    void generateChangelog(in string base_rev) {
        auto changes = getChanges(base_rev);
        repo.generateChangelog(
            PrepareReleaseResult(changes.repo_version, changes, base_rev));
        generateVersionFile(changes.repo_version, create: true);
    }

    /** Generate CHANGELOG.md and CHANGELOG.latest.md for a release.
      *
      * Stages both files; does NOT commit — the caller decides.
      **/
    void generateChangelog(in PrepareReleaseResult result) {
        infof("Assembly: Generating changelog for release %s ...",
            result.new_version);
        repo.generateChangelog(result);
        infof("Assembly: Changelog generated.");
    }

    /** Write the assembly version into the `VERSION` file and stage it.
      *
      * Output only: the value comes from the release being made, and is never
      * read back to decide a version. Like `ADDONS.md` the file is optional,
      * and its presence is the opt-in.
      *
      * Params:
      *     assembly_version = version to record.
      *     create = write the file even when it does not exist yet.
      **/
    void generateVersionFile(
            in OdooStdVersion assembly_version, in bool create=false) {
        if (!create && !version_path.exists)
            return;
        infof("Assembly: Writing VERSION (%s) ...", assembly_version);
        version_path.writeFile(assembly_version.toString ~ "\n");
        repo.add(version_path);
    }

    /** Generate ADDONS.md / ADDONS.csv listing the addons currently in dist.
      *
      * Params:
      *    md  = generate ADDONS.md
      *    csv = generate ADDONS.csv
      **/
    void generateAddonsList(in bool md=true, in bool csv=true) {
        auto rows = addonListRows(findAddons(dist_dir));
        if (md) {
            infof("Assembly: Generating ADDONS.md ...");
            auto md_path = path.join(ASSEMBLY_ADDONS_MD_PATH);
            md_path.writeFile("### Addons list\n\n" ~ renderMarkdownTable(rows));
            repo.add(md_path);
        }
        if (csv) {
            infof("Assembly: Generating ADDONS.csv ...");
            auto csv_path = path.join(ASSEMBLY_ADDONS_CSV_PATH);
            csv_path.writeFile(renderCsv(rows));
            repo.add(csv_path);
        }
    }

    /** Generate or update the Dockerfile.
      *
      * Params:
      *     assembly_version = version to stamp as the image version label.
      *         Taken from the release being made, so the label always matches
      *         the tag.
      **/
    void generateDockerfile(in string assembly_version) {
        infof("Assembly: Preparing Dockerfile...");
        auto assembly = this;
        // TODO: move to template, after darktemple will be ready for this
        auto handle_requirements_txt = path.join("requirements.txt").exists;
        auto handle_requirements_lock_txt = path.join(ASSEMBLY_REQUIREMENTS_LOCK).exists;
        auto assembly_source_url = repo.hasRemoteUrl("origin") ? repo.getRemoteUrl().toString : "";
        if (path.join("Dockerfile").exists) {
            /* The rendered template is inserted verbatim via the callback
             * overload: the replacement-format overload would read '$&',
             * '$1' and '${...}' in it as substitution tokens, which is
             * ordinary Dockerfile syntax (and throws when unbalanced).
             */
            auto dockerfile_tmpl = renderFile!("templates/assembly/Dockerfile.tmpl", assembly, handle_requirements_txt, handle_requirements_lock_txt, assembly_version, assembly_source_url);
            string dockerfile_content = path.join("Dockerfile")
                .readFileText
                .replaceFirst!(_ => dockerfile_tmpl)(
                    regex(".*# ---- ODOOD END DYNAMIC DOCKER CONFIG ----\n", "s"));
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
        } else if (spec.layout == AssemblyLayout.STANDARD
                && path.join(".dockerignore").readFileText
                    .splitLines
                    .map!(l => l.strip)
                    .canFind("/odood-assembly.yml", "odood-assembly.yml")) {
            /* The Dockerfile copies the spec into the image; excluding it keeps
             * it out of the build context and the COPY fails with a confusing
             * "not found" for a file that is plainly there. */
            warningf(
                "Assembly: .dockerignore excludes odood-assembly.yml, which " ~
                "the Dockerfile copies into the image. Remove that line, or " ~
                "the docker build will fail.");
        }
    }

    /// ditto
    void generateDockerfile() {
        // Outside a release, the most recent release is what the image
        // describes; unreleased assemblies get no version label.
        auto current = currentVersion;
        generateDockerfile(current.isNull ? "" : current.get.toString);
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
    void addSource(in GitURL git_url, in string name=null, in string git_ref=null,
            in string git_commit=null) {
        _spec.addSource(
            git_url: git_url, name: name, git_ref: git_ref, git_commit: git_commit);
    }

    /// Add addon to assembly
    void addAddon(in string name, in string source_name=null, in bool from_odoo_apps=false) {
        _spec.addAddon(name: name, source_name: source_name,  from_odoo_apps: from_odoo_apps);
    }

    /// Remove an addon from assembly by name. No-op if absent.
    void removeAddon(in string name) {
        _spec.removeAddon(name);
    }

    /// Remove a source from assembly. Refuses if any addon references it.
    void removeSource(in string name) {
        _spec.removeSource(name);
    }

    /// ditto
    void removeSource(in AssemblySpecSource source) {
        _spec.removeSource(source);
    }

    /// ditto
    void removeSource(in GitURL git_url, in string name=null,
            in string git_ref=null, in string git_commit=null) {
        _spec.removeSource(git_url, name, git_ref, git_commit);
    }

    /// Replace the source named `name` in place (re-pin); refuses a rename while
    /// addons reference it.
    void replaceSource(in string name, in GitURL git_url, in string new_name=null,
            in string git_ref=null, in string git_commit=null) {
        _spec.replaceSource(name, git_url, new_name, git_ref, git_commit);
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

    // generateAddonsList writes ADDONS.md / ADDONS.csv from the dist addons.
    import std.algorithm: canFind;
    assembly.generateAddonsList();
    assembly.path.join("ADDONS.md").exists.shouldBeTrue;
    assembly.path.join("ADDONS.csv").exists.shouldBeTrue;
    assembly.path.join("ADDONS.md").readFileText.canFind("| my_addon |").shouldBeTrue;
    assembly.path.join("ADDONS.csv").readFileText.canFind(`"my_addon"`).shouldBeTrue;
}


// Version resolution: release tags are authoritative, the VERSION file only
// bootstraps assemblies that predate them, and the file is written only when
// it already exists.
unittest {
    import unit_threaded.assertions;
    import thepath: createTempPath;
    import odood.git: GitURL;
    import odood.lib.assembly.source_provider: AssemblySourceProviderInterface;

    auto root = createTempPath;
    scope(exit) root.remove();

    auto src = root.join("fake-source");
    src.join("my_addon").mkdir(true);
    src.join("my_addon", "__init__.py").writeFile("");
    src.join("my_addon", "__manifest__.py").writeFile(
        `{"name": "my_addon", "version": "17.0.1.0.0", "depends": ["base"]}`);

    static class FakeProvider : AssemblySourceProviderInterface {
        Path src_path;
        this(Path p) { src_path = p; }
        override void ensureSources(in AssemblySpecSource[] sources, in OdooSerie serie) {}
        override Path resolveSource(in AssemblySpecSource source, in OdooSerie serie) {
            return src_path;
        }
        override Path resolveExternalAddon(in AssemblySpecAddon specAddon, in OdooSerie serie) {
            assert(false, "no external addons expected in this test");
        }
    }

    auto assembly_path = root.join("assembly");
    assembly_path.mkdir(true);
    auto assembly = Assembly.initialize(
        assembly_path, OdooSerie("17.0"), new FakeProvider(src));
    assembly.addSource(GitURL("https://example.test/repo"));
    assembly.addAddon("my_addon");
    assembly.save();

    assembly.repo.add(assembly.spec_path);
    assembly.repo.commit("Initial commit");
    immutable base_rev = assembly.repo.getCurrCommit;

    assembly.sync();

    // Never released: no tag, no VERSION file.
    assembly.currentVersion.isNull.shouldBeTrue;

    // Bootstraps at <serie>.0.0.0; an added addon is a MINOR bump.
    auto release = assembly.prepareRelease(base_rev);
    release.isNull.shouldBeFalse;
    release.get.new_version.toString.should == "17.0.0.1.0";
    release.get.start_ref.should == base_rev;

    // The file is opt-in: absent means absent.
    assembly.generateVersionFile(release.get.new_version);
    assembly.version_path.exists.shouldBeFalse;

    assembly.generateVersionFile(release.get.new_version, create: true);
    assembly.version_path.readFileText.should == "17.0.0.1.0\n";

    // With no tag yet, the file is what the version is read from.
    assembly.currentVersion.get.toString.should == "17.0.0.1.0";

    // Commit the assembled content so a tag can point at a tree containing it.
    assembly.repo.add(assembly.dist_dir);
    assembly.repo.commit("Release 17.0.0.1.0");

    // Once a tag exists it wins, whatever the file says.
    assembly.repo.setTag("17.0.3.0.0");
    assembly.currentVersion.get.toString.should == "17.0.3.0.0";

    // An existing file is updated without asking.
    assembly.generateVersionFile(OdooStdVersion("17.0.3.0.0"));
    assembly.version_path.readFileText.should == "17.0.3.0.0\n";

    // Nothing changed since the tagged commit.
    assembly.prepareRelease.isNull.shouldBeTrue;
}


// Migration: an assembly that has a VERSION file but no tag yet releases from
// the version the file records, and detects changes made since the file was
// last written — even when those changes are already committed on the branch.
unittest {
    import unit_threaded.assertions;
    import thepath: createTempPath;
    import theprocess: Process;
    import odood.git: GitURL;
    import odood.lib.assembly.source_provider: AssemblySourceProviderInterface;

    auto root = createTempPath;
    scope(exit) root.remove();

    auto src = root.join("fake-source");
    foreach(name; ["addon_one", "addon_two"]) {
        src.join(name).mkdir(true);
        src.join(name, "__init__.py").writeFile("");
        src.join(name, "__manifest__.py").writeFile(
            `{"name": "` ~ name ~ `", "version": "17.0.1.0.0", "depends": ["base"]}`);
    }

    static class FakeProvider : AssemblySourceProviderInterface {
        Path src_path;
        this(Path p) { src_path = p; }
        override void ensureSources(in AssemblySpecSource[] sources, in OdooSerie serie) {}
        override Path resolveSource(in AssemblySpecSource source, in OdooSerie serie) {
            return src_path;
        }
        override Path resolveExternalAddon(in AssemblySpecAddon specAddon, in OdooSerie serie) {
            assert(false, "no external addons expected in this test");
        }
    }

    auto assembly_path = root.join("assembly");
    assembly_path.mkdir(true);
    auto assembly = Assembly.initialize(
        assembly_path, OdooSerie("17.0"), new FakeProvider(src));
    assembly.addSource(GitURL("https://example.test/repo"));
    assembly.addAddon("addon_one");
    assembly.save();
    assembly.repo.add(assembly.spec_path);
    assembly.repo.commit("Initial commit");

    /* Give the assembly an origin holding the same commits, so the stable
     * branch is not behind: this is the state a release runs in once the sync
     * has been merged, and the case where comparing against the branch would
     * find nothing to release. */
    auto remote_path = root.join("remote.git");
    Process("git").withArgs("init", "--bare", remote_path.toString)
        .execute.ensureOk(true);
    assembly.repo.remoteAdd("origin", remote_path.toString);
    assembly.repo.gitCmd
        .withArgs("push", "-u", "origin", "HEAD:17.0").execute.ensureOk(true);

    // An assembly released under the old scheme: VERSION committed, no tag.
    assembly.sync();
    assembly.generateVersionFile(OdooStdVersion("17.0.2.3.0"), create: true);
    assembly.repo.add(assembly.dist_dir);
    assembly.repo.commit("Release 17.0.2.3.0");

    assembly.currentVersion.get.toString.should == "17.0.2.3.0";

    // A later sync, already committed to the branch the release runs on.
    assembly.addAddon("addon_two");
    assembly.save();
    assembly.sync();
    assembly.repo.add(assembly.spec_path);
    assembly.repo.add(assembly.dist_dir);
    assembly.repo.commit("[SYNC] Assembly synced");
    assembly.repo.gitCmd
        .withArgs("push", "origin", "HEAD:17.0").execute.ensureOk(true);
    assembly.repo.fetchOrigin("17.0");

    // The base is the commit that wrote VERSION, not the branch tip, so the
    // added addon is still visible: a MINOR bump from what the file recorded.
    auto release = assembly.prepareRelease;
    release.isNull.shouldBeFalse;
    release.get.new_version.toString.should == "17.0.2.4.0";

    assembly.generateVersionFile(release.get.new_version);
    assembly.version_path.readFileText.should == "17.0.2.4.0\n";
    assembly.repo.commit("Release 17.0.2.4.0");
    assembly.repo.setTag("17.0.2.4.0");

    // With a tag in place the file is no longer what decides the version.
    assembly.currentVersion.get.toString.should == "17.0.2.4.0";
    assembly.prepareRelease.isNull.shouldBeTrue;
}


// A never-released assembly releases from the start of history, so its first
// release works even though the content is already on the branch the release
// runs on. Also covers detecting a release that was tagged but not pushed.
unittest {
    import unit_threaded.assertions;
    import thepath: createTempPath;
    import theprocess: Process;
    import odood.git: GitURL;
    import odood.lib.assembly.source_provider: AssemblySourceProviderInterface;

    auto root = createTempPath;
    scope(exit) root.remove();

    auto src = root.join("fake-source");
    src.join("my_addon").mkdir(true);
    src.join("my_addon", "__init__.py").writeFile("");
    src.join("my_addon", "__manifest__.py").writeFile(
        `{"name": "my_addon", "version": "17.0.1.0.0", "depends": ["base"]}`);

    static class FakeProvider : AssemblySourceProviderInterface {
        Path src_path;
        this(Path p) { src_path = p; }
        override void ensureSources(in AssemblySpecSource[] sources, in OdooSerie serie) {}
        override Path resolveSource(in AssemblySpecSource source, in OdooSerie serie) {
            return src_path;
        }
        override Path resolveExternalAddon(in AssemblySpecAddon specAddon, in OdooSerie serie) {
            assert(false, "no external addons expected in this test");
        }
    }

    auto assembly_path = root.join("assembly");
    assembly_path.mkdir(true);
    auto assembly = Assembly.initialize(
        assembly_path, OdooSerie("17.0"), new FakeProvider(src));
    assembly.addSource(GitURL("https://example.test/repo"));
    assembly.addAddon("my_addon");
    assembly.save();
    assembly.repo.add(assembly.spec_path);
    assembly.repo.commit("Initial commit");

    auto remote_path = root.join("remote.git");
    Process("git").withArgs("init", "--bare", remote_path.toString)
        .execute.ensureOk(true);
    assembly.repo.remoteAdd("origin", remote_path.toString);
    assembly.repo.gitCmd
        .withArgs("push", "-u", "origin", "HEAD:17.0").execute.ensureOk(true);

    // Sync and commit, then push: the stable branch now holds the content, and
    // there is neither a tag nor a VERSION file to measure against.
    assembly.sync();
    assembly.repo.add(assembly.dist_dir);
    assembly.repo.commit("[SYNC] Assembly synced");
    assembly.repo.gitCmd
        .withArgs("push", "origin", "HEAD:17.0").execute.ensureOk(true);
    assembly.repo.fetchOrigin("17.0");

    assembly.currentVersion.isNull.shouldBeTrue;
    assembly.version_path.exists.shouldBeFalse;

    auto release = assembly.prepareRelease;
    release.isNull.shouldBeFalse;
    release.get.new_version.toString.should == "17.0.0.1.0";

    // Tagging without pushing: the next run must recognise the release rather
    // than measure from it and conclude there is nothing to do.
    assembly.releasedAtHead.isNull.shouldBeTrue;
    assembly.repo.setTag(release.get.new_version.toString);
    assembly.releasedAtHead.get.toString.should == "17.0.0.1.0";
    assembly.prepareRelease.isNull.shouldBeTrue;

    // A tag left behind on an older commit is not mistaken for one at HEAD.
    assembly.path.join("notes.txt").writeFile("later work");
    assembly.repo.add(Path("notes.txt"));
    assembly.repo.commit("Add notes");
    assembly.releasedAtHead.isNull.shouldBeTrue;
}
