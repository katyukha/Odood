module odood.git.repository;

private import std.typecons: Nullable, nullable;
private import std.exception: enforce;
private import std.string: chompPrefix, strip, empty, splitLines;
private import std.format: format;
private import std.algorithm: map;
private import std.array: array;
private static import std.process;

private import thepath: Path;

private import odood.exception: OdoodException;
private import theprocess;
private import odood.git: getGitTopLevel, GIT_REF_WORKTREE, GitURL;


/** Simple class to manage git repositories
  **/
class GitRepository {
    private const Path _path;

    @disable this();

    this(in Path path) {
        if (path.join(".git").exists)
            _path = path;
        else
            _path = getGitTopLevel(path);
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
    protected auto gitCmd() const {
        return Process("git")
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
            .setFlag(std.process.Config.Flags.stderrPassThrough)
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
            .setFlag(std.process.Config.stderrPassThrough)
            .execute()
            .ensureStatus(true)
            .output.strip();
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
            .setArgs("fetch", "origin", branch)
            .execute()
            .ensureStatus(true);
    }

    /** Get remote url for specified remote
      **/
    auto getRemoteUrl(in string name) const {
        string res = gitCmd
            .setArgs("remote", "get-url", name)
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

    /** Switch repo to specified branch
      **/
    void switchBranchTo(in string branch_name, in bool create=false) const {
        if (create)
            gitCmd
                .setArgs("checkout", "-b", branch_name)
                .execute()
                .ensureStatus(true);
        else
            gitCmd
                .setArgs("checkout", branch_name)
                .execute()
                .ensureStatus(true);
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

    /** Pull repository
      **/
    void pull() const {
        gitCmd
            .withArgs("pull")
            .execute()
            .ensureOk(true);
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
            cmd = cmd.addArgs("--staged");

        // Prepeare command for git diff
        if (start_rev !is null) {
            cmd = cmd.addArgs(prepareRevRange(start_rev, end_rev));
        }
        if (path_filters) {
            cmd = cmd.addArgs(["--"] ~ path_filters);
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
}

