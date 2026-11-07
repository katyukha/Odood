module odood.project.addons.repository_manager;

private import std.logger: warningf;
private import std.string: toLower;
private import std.algorithm: map;
private import std.array: array, split;
private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable;

private import std.file: SpanMode;

private import thepath: Path;

private import odood.project: Project;
private import odood.lib.addons.repository: AddonRepository;
private import odood.project.addons.manager:
    DEFAULT_INSTALL_PY_REQUIREMENTS, DEFAULT_INSTALL_MANIFEST_REQUIREMENTS;
private import odood.git: GitURL, parseGitURL, gitClone, isGitRepo;
private import odood.lib.git_credentials: GIT_CREDENTIALS_ENV, resolveGitCredentialEnv;
private import odood.exception: OdoodException;


/** Struct that provides API to manage the git repositories of a project —
  * the addon repositories under the project's `repositories/` directory.
  *
  * Addon-level work (scanning, linking, requirements) lives in AddonManager;
  * this manager owns the repository collection itself (get, add, ...).
  **/
struct RepositoryManager {
    private const Project _project;
    private const bool _test_mode;

    @disable this();

    this(in Project project, in bool test_mode=false) pure {
        _project = project;
        _test_mode = test_mode;
    }

    /** Get repository instance for the specified path.
      *
      * Params:
      *     path = path to the root of a git repository
      **/
    auto get(in Path path) const {
        enforce!OdoodException(
            path.join(".git").exists,
            "Is not a git root directory.");
        return new AddonRepository(path);
    }

    /** Recursively find addon repositories under the given directory.
      * Descends into subdirectories until a git repository is found.
      **/
    private AddonRepository[] searchRepositories(in Path dir) const {
        AddonRepository[] result;
        foreach(p; dir.walk(SpanMode.shallow)) {
            if (!p.isDir)
                continue;
            if (p.isGitRepo)
                result ~= new AddonRepository(p);
            else
                result ~= searchRepositories(p);
        }
        return result;
    }

    /** Enumerate all addon repositories under the project's `repositories/`
      * directory (recursively).
      **/
    AddonRepository[] list() const {
        if (!_project.directories.repositories.exists)
            return [];
        return searchRepositories(_project.directories.repositories);
    }

    /** Reopen `repo` with the credentials that `ODOOD_GIT_CREDENTIALS` holds
      * for its `origin`, for operations that reach the remote. Returns `repo`
      * itself when there are none.
      **/
    AddonRepository withCredentials(AddonRepository repo) const {
        if (!repo.hasRemoteUrl("origin"))
            return repo;

        Nullable!GitURL origin;
        // An origin that is not a URL, such as a local path, needs none.
        try origin = repo.getRemoteUrl;
        catch (OdoodException)
            return repo;

        auto env = resolveGitCredentialEnv(origin.get);
        return env.length ? new AddonRepository(repo.path, env) : repo;
    }

    /** Add a new addon repository to the project: clone it under
      * `repositories/`, link its addons, and optionally process its
      * odoo_requirements.txt to recursively fetch dependencies.
      *
      * If branch is not specified, the project's serie branch is cloned.
      *
      * Params:
      *     url = repository url to clone from
      *     branch = repository branch to clone
      *     single_branch = if set, clone only the single branch
      *     recursive = if set, process odoo_requirements.txt inside the cloned
      *         repo to recursively fetch its dependencies
      *     py_requirements = if set, install python requirements from
      *         requirements.txt
      *     manifest_requirements = if set, install python requirements from
      *         the addon manifest
      **/
    void add(
            in string url,
            in string branch,
            in bool single_branch=false,
            in bool recursive=true,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS) {

        auto git_url = parseGitURL(url);

        // A credential embedded in the URL would be stored in the clear in
        // the clone's git config and echoed in git's own error messages.
        enforce!OdoodException(
            !git_url.hasCredentials,
            ("Cannot add repository '%s': the URL contains embedded " ~
             "credentials. Use SSH, or set them in %s instead.").format(
                git_url, GIT_CREDENTIALS_ENV));

        auto dest = _project.directories.repositories.join(
                git_url.repoName.toLower.split("/"));

        if (dest.exists) {
            warningf(
                "Repository %s seems to be already cloned to %s. Skipping...",
                url, dest);
            return;
        }

        auto repo = gitClone(
            git_url, dest, branch, single_branch,
            env: resolveGitCredentialEnv(git_url));

        // Linking addons and processing requirements is addon-domain work,
        // delegated to the AddonManager.
        _project.addons(_test_mode).link(
            repo.path,
            true,   // recursive
            false,  // force
            py_requirements,
            manifest_requirements);

        // If there is an odoo_requirements.txt file present, process it.
        if (recursive && repo.path.join("odoo_requirements.txt").exists)
            _project.addons(_test_mode).processOdooRequirements(
                repo.path.join("odoo_requirements.txt"),
                single_branch,
                recursive,
                py_requirements,
                manifest_requirements);
    }

    /// ditto
    void add(
            in string url,
            in bool single_branch=false,
            in bool recursive=true,
            in bool py_requirements=DEFAULT_INSTALL_PY_REQUIREMENTS,
            in bool manifest_requirements=DEFAULT_INSTALL_MANIFEST_REQUIREMENTS) {
        add(
            url,
            _project.odoo.serie.toString,
            single_branch,
            recursive,
            py_requirements,
            manifest_requirements);
    }
}


// Test repository enumeration (no real git needed: isGitRepo treats a directory
// containing a .git/ entry as a repository).
unittest {
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;
    import std.algorithm: map, canFind;
    import std.array: array;
    import odood.utils.odoo.serie: OdooSerie;

    auto root = createTempPath;
    scope(exit) root.remove();

    auto project = new Project(root, OdooSerie(17));

    // No repositories/ directory yet → empty list.
    project.repositories.list().length.should == 0;

    auto repos_dir = root.join("repositories");
    repos_dir.join("acme", "repo1", ".git").mkdir(true);
    repos_dir.join("acme", "repo2", ".git").mkdir(true);
    // Nested repo under a non-repo subdir → exercises recursion.
    repos_dir.join("oca", "server-tools", ".git").mkdir(true);
    // A loose file at the top level → must be skipped, not crash.
    repos_dir.join("README.md").writeFile("hi");

    auto repos = project.repositories.list();
    repos.length.should == 3;

    auto names = repos.map!(r => r.path.relativeTo(repos_dir).toString).array;
    names.canFind("acme/repo1").shouldBeTrue;
    names.canFind("acme/repo2").shouldBeTrue;
    names.canFind("oca/server-tools").shouldBeTrue;
}

// withCredentials resolves the credentials from the origin, and leaves a
// repository whose origin is missing or not a URL as it is.
unittest {
    import std.process: environment;
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;
    import odood.git: GitRepository;
    import odood.git.credential: GIT_CREDENTIAL_PASSWORD_ENV;
    import odood.utils.odoo.serie: OdooSerie;

    immutable string[string] preset = [
        GIT_CREDENTIALS_ENV: "https://github.com/my-org user:org-token",
        // The origin is read as git uses it, after the user's `insteadOf`
        // rewrites, which may turn it into ssh.
        "GIT_CONFIG_GLOBAL": "/dev/null",
    ];
    auto saved = environment.toAA;
    foreach(key, value; preset)
        environment[key] = value;
    scope(exit) foreach(key; preset.keys) {
        if (auto old = key in saved)
            environment[key] = *old;
        else
            environment.remove(key);
    }

    auto root = createTempPath;
    scope(exit) root.remove();
    auto project = new Project(root, OdooSerie(17));

    AddonRepository repo(in string name, in string origin) {
        auto result = new AddonRepository(
            GitRepository.initialize(root.join("repositories", name)));
        if (origin)
            result.remoteAdd("origin", origin);
        return result;
    }

    project.repositories.withCredentials(repo("private", "https://github.com/my-org/repo"))
        .env[GIT_CREDENTIAL_PASSWORD_ENV].shouldEqual("org-token");

    foreach(listed; [
            repo("public", "https://github.com/other/repo"),
            repo("mirror", root.join("mirror").toString),
            repo("local", null)])
        (project.repositories.withCredentials(listed) is listed).shouldBeTrue;
}
