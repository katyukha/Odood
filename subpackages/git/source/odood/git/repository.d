module odood.git.repository;

private import std.typecons: Nullable, nullable;
private import std.exception: enforce;
private import std.string: chompPrefix, strip, empty, splitLines, toLower;
private import std.format: format;
private import std.algorithm: map, canFind, startsWith, filter;
private import std.array: array;
private import std.regex: ctRegex, matchFirst;
private import std.conv: to;
private static import std.process;


private import thepath: Path;

private import odood.exception: OdoodException;
private import theprocess;
private import odood.git: getGitTopLevel, GIT_REF_WORKTREE, GitURL;


/** Representation of result of `git status` command.
  **/
protected struct GitStatus {
    bool hasChanges = false;
    bool hasUntracked = false;
    bool hasConflicts = false;
    int ahead = 0;
    int behind = 0;
    string localBranch;
    string remoteBranch;

    /** Check if repository is clean:
      * - no untracked files
      * - no conflicts
      * - no changes
      **/
    bool isClean() const {
        return !hasChanges && !hasUntracked && !hasConflicts;
    }

    /** Check if repo is in diverged status
      **/
    bool isDiverged() const {
        return ahead > 0 && behind > 0;
    }
}

/** Simple class to manage git repositories
  **/
class GitRepository {
    private const Path _path;
    private const string[string] _env;

    @disable this();

    /** Git repository constructor
      *
      * Parametrs:
      *     path = path to git repository
      *     env = optional dict with additional environment variables to be applied for each git operation.
      *           This could be used to pass access tokens for example.
      **/
    this(in Path path, in string[string] env=null) {
        if (path.join(".git").exists)
            _path = path.toAbsolute;
        else
            _path = getGitTopLevel(path);

        // Copy env
        string[string] tmp_env;
        foreach(i; env.byKeyValue)
            tmp_env[i.key] = i.value;
        _env = tmp_env;
    }

    /// Return path for this repo
    auto path() const => _path;

    /// Make path relative to repo path
    private auto _makeRelPath(in Path path) const {
        if (path.isAbsolute)
            enforce!OdoodException(
                path.isInside(_path),
                "Path must be inside repo!");
            return path.relativeTo(_path);
        return path;
    }

    /// Preconfigured runner for git CLI
    auto gitCmd() const {
        return Process("git")
            .withEnv(_env)
            .inWorkDir(_path);
    }

    /** Initialize empty git repo
      *
      * Params:
      *     path = path to directory where git repository have to be initialized.
      *
      * Returns: GitRepository instance
      **/
    static auto initialize(in Path path) {
        Process("git").withArgs("init", path.toString).execute.ensureOk(true);
        return new GitRepository(path);
    }

    /** Find the name of current git branch for this repo.
      *
      * Returns: Nullable!string
      *     If current branch is detected, result is non-null.
      *     If result is null, then git repository is in detached-head mode.
      **/
    Nullable!string getCurrBranch() const {
        auto result = gitCmd
            .withArgs(["symbolic-ref", "-q", "HEAD"])
            .withFlag(std.process.Config.Flags.stderrPassThrough)
            .execute();
        if (result.status == 0)
            return result.output.strip().chompPrefix("refs/heads/").nullable;
        return Nullable!(string).init;
    }

    /** Get current commit
      *
      * Returns:
      *     SHA1 hash of current commit
      **/
    string getCurrCommit() const {
        return gitCmd
            .withArgs(["rev-parse", "-q", "HEAD"])
            .withFlag(std.process.Config.stderrPassThrough)
            .execute()
            .ensureStatus(true)
            .output.strip();
    }

    /** Verify that current HEAD matches the expected commit hash.
      *
      * Throws: OdoodException if the hash is too short or HEAD does not match.
      **/
    void ensureAtCommit(in string expected) const {
        enum size_t MIN_COMMIT_LENGTH = 12;
        enforce!OdoodException(
            expected.length >= MIN_COMMIT_LENGTH,
            "Commit hash too short: '%s' (%d chars), minimum %d required".format(
                expected, expected.length, MIN_COMMIT_LENGTH));
        auto actual = getCurrCommit();
        enforce!OdoodException(
            actual.startsWith(expected.toLower),
            "Commit mismatch: expected %s, HEAD is %s".format(expected, actual));
    }

    /** Fetch remote 'origin'
      **/
    void fetchOrigin() const {
        gitCmd
            .withArgs("fetch", "origin")
            .execute()
            .ensureStatus(true);
    }

    /// ditto
    void fetchOrigin(in string branch) const {
        gitCmd
            .withArgs("fetch", "origin", branch)
            .execute()
            .ensureStatus(true);
    }

    /** Check if repo has configured remote url with specified name
      **/
    auto hasRemoteUrl(in string name) const {
        return gitCmd
            .withArgs("remote", "get-url", name)
            .withFlag(std.process.Config.stderrPassThrough)
            .execute
            .isOk;
    }

    /** Get remote url for specified remote
      **/
    auto getRemoteUrl(in string name) const {
        string res = gitCmd
            .withArgs("remote", "get-url", name)
            .withFlag(std.process.Config.stderrPassThrough)
            .execute
            .ensureOk(true)
            .output.strip;
        return GitURL(res);
    }

    /// ditto
    auto getRemoteUrl() const {
        return getRemoteUrl("origin");
    }

    /** Check if repo has local branch with specified name
      **/
    bool hasLocalBranch(in string name) const {
        return gitCmd
            .withArgs("show-ref", "--verify", "--quiet", "refs/heads/%s".format(name))
            .withFlag(std.process.Config.stderrPassThrough)
            .execute
            .isOk;
    }

    /** Switch repo to specified branch
      **/
    void switchBranchTo(in string branch_name, in bool create=false) const {
        if (create)
            gitCmd
                .withArgs("checkout", "-b", branch_name)
                .execute()
                .ensureStatus(true);
        else
            gitCmd
                .withArgs("checkout", branch_name)
                .execute()
                .ensureStatus(true);
    }

    /** Checkout specific files to specific version
      **/
    void checkoutFile(in string branch_name, in bool force, in Path[] paths...) const
    in (paths.length > 0, "At least one path must be specified") {
        auto cmd = gitCmd.withArgs("checkout");
        if (force)
            cmd.addArgs("-f");
        cmd.addArgs(branch_name, "--");
        foreach(path; paths)
            cmd.addArgs(path.toString);
        cmd.execute.ensureOk(true);
    }

    /// ditto
    void checkoutFile(in string branch_name, in Path[] paths...) const {
        checkoutFile(branch_name, false, paths);
    }

    /** Add path (files) to git repo index
      **/
    void add(in Path path) const {
        gitCmd
            .withArgs("add", _makeRelPath(path).toString)
            .execute
            .ensureOk(true);
    }

    /** Remove path (files) from git repo index
      **/
    void remove(in Path path, in bool recursive=false, in bool force=false, in bool ignore_unmatch=false) const {
        auto cmd = gitCmd.withArgs("rm");
        if (recursive)
            cmd.addArgs("-r");
        if (force)
            cmd.addArgs("--force");
        if (ignore_unmatch)
            cmd.addArgs("--ignore-unmatch");
        cmd.addArgs(path.toString);
        cmd.execute.ensureOk(true);
    }

    /** Commit changes to git repository
      **/
    void commit(in string message, in string username=null, in string useremail=null) const {
        auto cmd = gitCmd;
        if (!username.empty)
            cmd.addArgs("-c", "user.name='%s'".format(username));
        if (!useremail.empty)
            cmd.addArgs("-c", "user.email='%s'".format(useremail));

        cmd.addArgs("commit", "-m", message);
        cmd.execute.ensureOk(true);
    }

    /** List all tag names visible on the given remote. **/
    string[] listRemoteTags(in string remote = "origin") const {
        import odood.git: gitListRemoteTags;
        return gitListRemoteTags(getRemoteUrl(remote).toString);
    }

    /** List all local tag names in the repository. **/
    string[] listLocalTags() const {
        auto output = gitCmd
            .withArgs("tag", "--list")
            .execute
            .ensureOk(true)
            .output;
        return output.splitLines.map!(l => l.strip).filter!(l => l.length > 0).array;
    }

    /** Set annotation tag on current commit in repo
      **/
    void setTag(in string tag_name, in string message = null)  const
    in (tag_name.length > 0) {
        // TODO: add ability to set tag on specific commit
        gitCmd
            .withArgs(
                "tag",
                "-a", tag_name,
                "-m", message.length > 0 ? message : tag_name)
            .execute()
            .ensureOk(true);
    }

    /** Push a specific tag to a remote (default: origin). **/
    void pushTag(in string tag_name, in string remote = "origin") const
    in (tag_name.length > 0) {
        gitCmd
            .withArgs("push", remote, tag_name)
            .execute
            .ensureOk("Cannot push tag %s to %s".format(tag_name, remote), true);
    }

    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        // Create a bare "remote" repo and a local clone
        auto remote_path = root.join("remote.git");
        Process("git").withArgs("init", "--bare", remote_path.toString).execute.ensureOk(true);

        auto local_path = root.join("local");
        auto repo = GitRepository.initialize(local_path);
        local_path.join("file.txt").writeFile("hello");
        repo.add(local_path.join("file.txt"));
        repo.commit("Init");

        // Point origin at the bare remote and push the initial branch
        repo.gitCmd.withArgs("remote", "add", "origin", remote_path.toString).execute.ensureOk(true);
        repo.gitCmd.withArgs("push", "-u", "origin", "HEAD").execute.ensureOk(true);

        // No tags yet
        repo.listLocalTags().should == cast(string[])[];

        // Create two annotated tags
        repo.setTag("17.0.1.0.0");
        repo.setTag("17.0.1.0.1");
        repo.listLocalTags().length.should == 2;
        repo.listLocalTags().canFind("17.0.1.0.0").shouldBeTrue;
        repo.listLocalTags().canFind("17.0.1.0.1").shouldBeTrue;

        // pushTag sends a tag to the remote
        repo.pushTag("17.0.1.0.0");

        // Verify the remote sees the tag via gitListRemoteTags
        import odood.git: gitListRemoteTags;
        auto remote_tags = gitListRemoteTags(remote_path.toString);
        remote_tags.canFind("17.0.1.0.0").shouldBeTrue;
        remote_tags.canFind("17.0.1.0.1").shouldBeFalse;  // not pushed yet

        // Push the second tag and verify
        repo.pushTag("17.0.1.0.1");
        auto remote_tags2 = gitListRemoteTags(remote_path.toString);
        remote_tags2.canFind("17.0.1.0.1").shouldBeTrue;
        remote_tags2.length.should == 2;
    }

    /** Pull repository
      **/
    void pull(in bool ff_only=false) const {
        auto cmd = gitCmd
            .withArgs("pull");
        if (ff_only)
            cmd.addArgs("--ff-only");

        cmd.execute().ensureOk(true);
    }

    /** Prepare git diff revision spec.
      *
      * Just return combination of start..end
      **/
    auto prepareRevRange(in string start_rev, in string end_rev) const {
        /* If end_rev is working tree, then we just pass start rev to git diff command.
         */
        if (end_rev == GIT_REF_WORKTREE)
            return start_rev;
        return "%s..%s".format(start_rev, end_rev);
    }

    /// ditto
    auto prepareRevRange(in string start) const {
        return prepareRevRange(start, GIT_REF_WORKTREE);
    }

    /** Check if repo has changes since last commit
      **/
    bool hasChanges() const {
        return gitCmd.withArgs("diff-index", "--quiet", "HEAD", "--")
            .execute
            .status != 0;
    }

    /** Get changed files
      **/
    auto getChangedFiles(in string start_rev, in string end_rev, in string[] path_filters=null, in bool staged=false) const {
        auto cmd = this.gitCmd
            .withArgs("diff", "--name-only")
            .withFlag(std.process.Config.stderrPassThrough);

        if (staged)
            cmd.addArgs("--staged");

        // Prepeare command for git diff
        if (start_rev !is null) {
            cmd.addArgs(prepareRevRange(start_rev, end_rev));
        }
        if (path_filters) {
            cmd.addArgs(["--"] ~ path_filters);
        }

        return cmd.execute.ensureOk(true).output.splitLines.map!((p) => Path(p)).array;
    }

    /// ditto
    auto getChangedFiles(in string start_rev, in string[] path_filters=null, in bool staged=false) const {
        return getChangedFiles(start_rev, GIT_REF_WORKTREE, path_filters, staged);
    }

    /// ditto
    auto getChangedFiles(in string[] path_filters=null, in bool staged=false) const {
        return getChangedFiles(null, GIT_REF_WORKTREE, path_filters, staged);
    }

    /// Test how get getChangedFiles works
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto git_root = root.join("test-repo");
        auto git_repo = GitRepository.initialize(git_root);

        git_repo.path.should == git_root;
        git_repo.hasChanges.shouldBeTrue();

        git_root.join("test_file.txt").writeFile("Hello world!\n");
        git_repo.hasChanges.shouldBeTrue();
        git_repo.getChangedFiles().should == Path[].init;
        git_repo.getChangedFiles(staged: true).should == Path[].init;

        git_repo.add(git_root.join("test_file.txt"));
        git_repo.hasChanges.shouldBeTrue();
        git_repo.getChangedFiles().should == Path[].init;
        git_repo.getChangedFiles(staged: true).should == [Path("test_file.txt")];

        git_repo.commit("Init");
        git_repo.getChangedFiles().should == Path[].init;
        git_repo.hasChanges.shouldBeFalse();

        auto rev_v1 = git_repo.getCurrCommit();

        git_root.join("test_file.txt").appendFile("Some extra text.\n");
        git_repo.getChangedFiles().should == [Path("test_file.txt")];
        git_repo.hasChanges.shouldBeTrue();

        git_repo.add(Path("test_file.txt"));
        git_repo.getChangedFiles().should == Path[].init;
        git_repo.getChangedFiles(staged: true).should == [Path("test_file.txt")];
        git_repo.hasChanges.shouldBeTrue();

        // test_file_2 create, but not added in repo
        git_root.join("test_file_2.txt").writeFile("Some text 2.\n");
        git_repo.getChangedFiles().should == Path[].init;
        git_repo.getChangedFiles(staged: true).should == [Path("test_file.txt")];
        git_repo.hasChanges.shouldBeTrue();

        // add file to repo
        git_repo.add(Path("test_file_2.txt"));
        git_repo.getChangedFiles().should == Path[].init;
        git_repo.getChangedFiles(staged: true).should == [Path("test_file.txt"), Path("test_file_2.txt")];
        git_repo.hasChanges.shouldBeTrue();

        git_repo.commit("V2");
        git_repo.getChangedFiles().should == Path[].init;
        git_repo.getChangedFiles(rev_v1).should == [Path("test_file.txt"), Path("test_file_2.txt")];
        git_repo.getChangedFiles(rev_v1, staged: true).should == [Path("test_file.txt"), Path("test_file_2.txt")];
        git_repo.hasChanges.shouldBeFalse();

        auto rev_v2 = git_repo.getCurrCommit();

        git_repo.getChangedFiles(rev_v1, rev_v2).should == [Path("test_file.txt"), Path("test_file_2.txt")];

        git_root.join("test_file_3.txt").writeFile("Some text 3.\n");
        git_repo.getChangedFiles().should == Path[].init;
        git_repo.getChangedFiles(rev_v2).should == Path[].init;
        git_repo.getChangedFiles(rev_v1).should == [Path("test_file.txt"), Path("test_file_2.txt")];
        git_repo.hasChanges.shouldBeFalse();  // test_file_3.txt is not in index.

        git_repo.add(Path("test_file_3.txt"));
        git_repo.getChangedFiles().should == Path[].init;
        git_repo.getChangedFiles(staged: true).should == [Path("test_file_3.txt")];
        git_repo.getChangedFiles(rev_v2).should == [Path("test_file_3.txt")];
        git_repo.getChangedFiles(rev_v2, staged: true).should == [Path("test_file_3.txt")];
        git_repo.getChangedFiles(rev_v1).should == [Path("test_file.txt"), Path("test_file_2.txt"), Path("test_file_3.txt")];
        git_repo.getChangedFiles(rev_v1, staged: true).should == [Path("test_file.txt"), Path("test_file_2.txt"), Path("test_file_3.txt")];
        git_repo.hasChanges.shouldBeTrue();
    }

    /** Walk up the directory tree from `path`, looking for a file named `name`
      * at each level. Checks existence in `rev` (defaults to worktree).
      *
      * Returns: path relative to repo root of the first match, or null.
      **/
    Nullable!Path searchFileUp(in Path path, in string name, in string rev = GIT_REF_WORKTREE) const {
        auto current = _makeRelPath(path);
        while (current.toString != ".") {
            auto candidate = current.join(name);
            if (isFileExists(candidate, rev))
                return candidate.nullable;
            current = current.parent(false);
        }
        return Nullable!Path.init;
    }

    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto git_root = root.join("test-repo");
        auto repo = GitRepository.initialize(git_root);

        // Set up: addon_a/models/sale.py, addon_a/__manifest__.py
        git_root.join("addon_a").mkdir(false);
        git_root.join("addon_a", "models").mkdir(false);
        git_root.join("addon_a", "__manifest__.py").writeFile("{}");
        git_root.join("addon_a", "models", "sale.py").writeFile("# model");
        repo.add(git_root.join("addon_a"));
        repo.commit("Init");
        auto rev_v1 = repo.getCurrCommit();

        // Worktree: finds manifest walking up from models/
        auto found = repo.searchFileUp(Path("addon_a/models"), "__manifest__.py");
        found.isNull.shouldBeFalse;
        found.get.should == Path("addon_a/__manifest__.py");

        // Worktree: not found when starting above the addon
        repo.searchFileUp(Path("addon_a"), "nonexistent.txt").isNull.shouldBeTrue;

        // Historical ref: finds manifest in rev_v1
        auto found_rev = repo.searchFileUp(Path("addon_a/models"), "__manifest__.py", rev_v1);
        found_rev.isNull.shouldBeFalse;
        found_rev.get.should == Path("addon_a/__manifest__.py");

        // Historical ref: file removed in worktree but still found in old ref
        git_root.join("addon_a", "__manifest__.py").remove();
        repo.searchFileUp(Path("addon_a/models"), "__manifest__.py").isNull.shouldBeTrue;
        repo.searchFileUp(Path("addon_a/models"), "__manifest__.py", rev_v1).isNull.shouldBeFalse;
    }

    /** Check if file specified by path exists in rev
      **/
    auto isFileExists(in Path path, in string rev) const {
        if (rev == GIT_REF_WORKTREE)
            return _path.join(_makeRelPath(path)).exists;
        return gitCmd
            .withArgs(
                "cat-file", "-e", "%s:%s".format(rev,  _makeRelPath(path)))
            .execute
            .isOk;
    }

    /// ditto
    auto isFileExists(in Path path) const {
        return isFileExists(path, GIT_REF_WORKTREE);
    }

    /** Get content of file for specified revision
      *
      * NOTE: This func read content as text
      **/
    auto getContent(in Path path, in string rev) const {
        if (rev == GIT_REF_WORKTREE)
            return _path.join(_makeRelPath(path)).readFileText();
        return gitCmd
            .withArgs(
                "show", "-q", "%s:./%s".format(rev, _makeRelPath(path)))
            .withFlag(std.process.Config.stderrPassThrough)
            .execute
            .ensureOk(true)
            .output;
    }

    /// ditto
    auto getContent(in Path path) const {
        return getContent(path, GIT_REF_WORKTREE);
    }

    /// Test how get Content works
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto git_root = root.join("test-repo");
        auto git_repo = GitRepository.initialize(git_root);

        git_repo.path.should == git_root;

        git_repo.isFileExists(git_root.join("test_file.txt")).shouldBeFalse();
        git_root.join("test_file.txt").writeFile("Hello world!\n");
        git_repo.isFileExists(git_root.join("test_file.txt")).shouldBeTrue();
        git_repo.add(git_root.join("test_file.txt"));
        git_repo.commit("Init");

        auto rev_v1 = git_repo.getCurrCommit();

        git_repo.isFileExists(git_root.join("test_file.txt"), rev_v1);

        // Test content of V1
        git_repo.getContent(git_root.join("test_file.txt"), rev_v1).should == "Hello world!\n";
        git_repo.getContent(Path("test_file.txt"), rev_v1).should == "Hello world!\n";

        // Test content of version in working tree
        git_repo.getContent(git_root.join("test_file.txt")).should == "Hello world!\n";
        git_repo.getContent(Path("test_file.txt")).should == "Hello world!\n";

        // Update test file and add to git
        git_root.join("test_file.txt").appendFile("Some extra text.\n");
        git_repo.add(Path("test_file.txt"));

        // test_file_2 create, but not added in repo
        git_repo.isFileExists(git_root.join("test_file_2.txt")).shouldBeFalse;
        git_repo.isFileExists(git_root.join("test_file_2.txt"), rev_v1).shouldBeFalse;
        git_root.join("test_file_2.txt").writeFile("Some text 2.\n");
        git_repo.isFileExists(git_root.join("test_file_2.txt")).shouldBeTrue;
        git_repo.isFileExists(git_root.join("test_file_2.txt"), rev_v1).shouldBeFalse;

        // add test_file_2 to repo
        git_repo.add(Path("test_file_2.txt"));
        git_repo.isFileExists(git_root.join("test_file_2.txt")).shouldBeTrue;
        git_repo.isFileExists(git_root.join("test_file_2.txt"), rev_v1).shouldBeFalse;

        git_repo.commit("V2");
        auto rev_v2 = git_repo.getCurrCommit();

        // Test text_file_2 exists
        git_repo.isFileExists(git_root.join("test_file_2.txt")).shouldBeTrue;
        git_repo.isFileExists(git_root.join("test_file_2.txt"), rev_v1).shouldBeFalse;
        git_repo.isFileExists(git_root.join("test_file_2.txt"), rev_v2).shouldBeTrue;

        // Test content of V1
        git_repo.getContent(git_root.join("test_file.txt"), rev_v1).should == "Hello world!\n";
        git_repo.getContent(Path("test_file.txt"), rev_v1).should == "Hello world!\n";

        // Test content of V2
        git_repo.getContent(git_root.join("test_file.txt"), rev_v2).should == "Hello world!\nSome extra text.\n";
        git_repo.getContent(Path("test_file.txt"), rev_v2).should == "Hello world!\nSome extra text.\n";

        // Test content of version in working tree
        git_repo.getContent(git_root.join("test_file.txt")).should == "Hello world!\nSome extra text.\n";
        git_repo.getContent(Path("test_file.txt")).should == "Hello world!\nSome extra text.\n";
    }

    /// Push current branch to a remote, optionally to a different branch name.
    void push(in string branch_name=null, in string remote="origin") const {
        auto current_branch = getCurrBranch();
        enforce!OdoodException(
            !current_branch.isNull,
            "Repository push operation is not allowed in detached tree mode");

        if (branch_name)
            gitCmd
                .withArgs(
                    "push", remote, "%s:%s".format(current_branch.get, branch_name))
                .execute
                .ensureOk("Cannot push changes to %s branch".format(branch_name), true);
        else
            gitCmd
                .withArgs(
                    "push", remote, current_branch.get)
                .execute
                .ensureOk("Cannot push changes to %s branch".format(branch_name), true);
    }

    /** Check git status and return minimal status information
      **/
    auto status() const {
        // TODO: Split parsing of status output to separate method/function and add unittests for it.
        //       Or, may be move parsing to struct GitStatus
        auto status_str = gitCmd
            .withEnv("LC_ALL", "C")
            .withArgs("status", "--untracked-files=all", "--porcelain", "--branch")
            .execute
            .ensureOk("Cannot get git status", true)
            .output;

        GitStatus status;
        auto lines = status_str.splitLines();
        if (lines.length == 0) return status;

        // Example: ## main...origin/main [ahead 1, behind 2]
        auto header = lines[0];

        /* Regex description
         * 1. (?P<local>[^\s\.]+) - local branch name
         * 2. (?:\.\.\.(?P<remote>[^\s\[]+))? - optional remote branch name (separated from local branch via '...)
         * 3. statistics ahead/behind that is used to check for diverged state
         *
         * Sample: ## main...origin/main [ahead 1, behind 2]
         */
        auto headerRegex = ctRegex!(r"^##\s+(?P<local>[^\s\.]+)(?:\.\.\.(?P<remote>[^\s\[]+))?(?:\s+\[(?:ahead\s+(?P<ahead>\d+))?(?:,\s+)?(?:behind\s+(?P<behind>\d+))?\])?");

        if (auto m = lines[0].matchFirst(headerRegex)) {
            status.localBranch = m["local"];
            status.remoteBranch = m["remote"].length ? m["remote"] : null;

            if (m["ahead"].length) status.ahead = m["ahead"].to!int;
            if (m["behind"].length) status.behind = m["behind"].to!int;
        }

        foreach (line; lines[1..$]) {
            if (line.length < 3)
                /* Minimal meaningful line is `XY PATH`, where:
                 *   X - status in index,
                 *   Y - status in tree,
                 *   PATH - file path separated by space.
                 *
                 * Thus, here we skip empty or unparsable lines.
                 */
                continue;
            if (["DD", "AU", "UD", "UA", "DU", "AA", "UU"].canFind(line[0 .. 2]))
                status.hasConflicts = true;
            else if (line.startsWith("??"))
                status.hasUntracked = true;
            else
                // "M ", " A", "D " ...
                status.hasChanges = true;  
        }
        return status;
    }
}
