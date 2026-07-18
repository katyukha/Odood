module odood.lib.assembly.source_provider_cached;

/** Default `AssemblySourceProviderInterface` implementation: clones/fetches git
  * sources into a local cache directory and downloads standalone addons from
  * Odoo Apps. This is odood's historical assembly source behaviour, lifted out
  * of `Assembly` behind the provider interface.
  **/

private import std.exception: enforce;
private import std.format: format;
private import std.logger: infof;
private import std.parallelism: taskPool;

private import darkarchive: DarkArchiveReader, DarkArchiveFormat;
private import thepath: Path, createTempPath;

private import odood.git: gitClone, GitRepository, isGitRepo;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.addons.addon: findAddons, isOdooAddon;
private import odood.utils: download;
private import odood.lib.assembly.exception: OdoodAssemblyException;
private import odood.lib.assembly.spec: AssemblySpecSource, AssemblySpecAddon;
private import odood.lib.assembly.source_provider: AssemblySourceProviderInterface;
private import odood.lib.assembly.source_env: resolveSourceGitEnv;


/** Clone/fetch git sources into `<cache_dir>/sources/<hash>` and download
  * standalone addons into `<cache_dir>/addons/<name>`. The cache persists
  * across builds (there is no teardown), so repeated builds are incremental.
  **/
final class AssemblySourceProviderCached : AssemblySourceProviderInterface {
    private Path _cache_dir;

    // Sources materialized this lifetime (by hashString). `synchronized` since
    // ensureSources resolves in parallel; the same source is never resolved
    // concurrently (distinct sources in ensureSources; sequential thereafter).
    private bool[string] _resolved_sources;

    this(in Path cache_dir) {
        _cache_dir = cache_dir;
    }

    /// Cache directory backing this provider.
    @property cache_dir() const => _cache_dir;

    private Path getSourceCachePath(in AssemblySpecSource source) const {
        cache_dir.join("sources").mkdir(true);
        return cache_dir.join("sources", source.hashString);
    }

    private Path getAddonCachePath(in string addon_name) const {
        cache_dir.join("addons").mkdir(true);
        return cache_dir.join("addons", addon_name);
    }

    override void ensureSources(in AssemblySpecSource[] sources, in OdooSerie serie) {
        infof("Assembly: syncing sources...");
        foreach(source; taskPool.parallel(sources))
            resolveSource(source, serie);
        infof("Assembly: all sources synced.");
    }

    override Path resolveSource(in AssemblySpecSource source, in OdooSerie serie) {
        auto repo_path = getSourceCachePath(source);
        synchronized(this) {
            if (source.hashString in _resolved_sources)
                return repo_path;
        }

        infof("Assembly: syncing source %s ...", source);
        if (repo_path.exists && !repo_path.isGitRepo)
            repo_path.remove();
        if (repo_path.exists) {
            auto repo = new GitRepository(repo_path, env: resolveSourceGitEnv(source));
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
                env: resolveSourceGitEnv(source));
            if (source.git_commit) {
                repo.switchBranchTo(source.git_commit);
                repo.ensureAtCommit(source.git_commit);
            }
        }
        infof("Assembly: source %s synced.", source);

        synchronized(this)
            _resolved_sources[source.hashString] = true;
        return repo_path;
    }

    override Path resolveExternalAddon(in AssemblySpecAddon specAddon, in OdooSerie serie) {
        auto cache_path = getAddonCachePath(specAddon.name);
        if (cache_path.exists)
            return cache_path;

        auto temp_dir = createTempPath();
        scope(exit) temp_dir.remove();

        auto download_path = temp_dir.join("%s.zip".format(specAddon.name));
        infof("Downloading addon %s from odoo apps...", specAddon.name);
        download(
            "https://apps.odoo.com/loempia/download/%s/%s/%s.zip?deps".format(
                specAddon.name, serie, specAddon.name),
            download_path);
        infof("Unpacking addon %s from odoo apps...", specAddon.name);
        DarkArchiveReader!(DarkArchiveFormat.zip)(download_path.toAbsolute).extractTo(temp_dir.join("apps"));

        enforce!OdoodAssemblyException(
            isOdooAddon(temp_dir.join("apps", specAddon.name)),
            "Downloaded archive does not contain requested odoo app!");

        foreach(addon; findAddons(temp_dir.join("apps"))) {
            auto addon_cache_path = getAddonCachePath(addon.name);
            if (!addon_cache_path.exists)
                addon.path.copyTo(addon_cache_path);
        }

        enforce!OdoodAssemblyException(
            cache_path.exists,
            "Addon %s download failed!".format(specAddon.name));
        return cache_path;
    }
}
