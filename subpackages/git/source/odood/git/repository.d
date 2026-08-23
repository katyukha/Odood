module odood.git.repository;

private import std.typecons: Nullable, nullable;
private import std.exception: enforce;
private import std.string: chompPrefix, strip, empty, splitLines, toLower;
private import std.format: format;
private import std.algorithm: map, canFind, startsWith, filter;
private import std.array: array;
private import std.conv: to;
private static import std.process;


private import thepath: Path;

private import odood.exception: OdoodException;
private import theprocess;
private import odood.git: getGitTopLevel, gitProcess, GIT_REF_WORKTREE, GitURL;
private import odood.git.remote: GitRemote;

// Re-exported for compatibility: these types used to be defined here.
public import odood.git.status: GitStatus;
public import odood.git.refs: GitTag, GitRef;


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

    /// Preconfigured runner for git CLI.
    /// Locale is pinned to C so git's output and error text is stable for
    /// parsing regardless of the user's locale (an explicit LC_ALL in the
    /// repo's env still wins, as _env is applied on top).
    auto gitCmd() const {
        return gitProcess
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
        gitProcess.withArgs("init", path.toString).execute.ensureOk(true);
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

    /** Resolve `commitish` to a commit SHA in this repository.
      *
      * A non-throwing probe: lets a caller pick between a plain ref and its
      * `origin/`-qualified spelling before acting on it. Annotated tags are
      * peeled to the tagged commit.
      *
      * Returns:
      *     Full SHA of the commit, or an empty string when `commitish`
      *     does not resolve.
      **/
    string tryRevParse(in string commitish) const {
        auto result = gitCmd
            .withArgs(
                "rev-parse", "--verify", "--quiet", commitish ~ "^{commit}")
            .execute();
        if (result.status != 0)
            return "";
        return result.output.strip();
    }

    /** Check if `ancestor` is reachable from `descendant` — i.e. whether the
      * former has been merged into the latter (`git merge-base --is-ancestor`).
      *
      * A ref that does not resolve answers false rather than throwing, since
      * callers ask about refs that may have vanished.
      **/
    bool isAncestor(in string ancestor, in string descendant) const {
        if (tryRevParse(ancestor).empty || tryRevParse(descendant).empty)
            return false;
        return gitCmd
            .withArgs("merge-base", "--is-ancestor", ancestor, descendant)
            .execute()
            .isOk;
    }

    /// Test tryRevParse + isAncestor
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto repo = GitRepository.initialize(root.join("repo"));
        repo.path.join("f.txt").writeFile("v1");
        repo.add(repo.path.join("f.txt"));
        repo.commit("initial");
        immutable first = repo.getCurrCommit;

        // Annotated tag on the first commit — must peel to that commit.
        repo.setTag("17.0.1.0.0");

        repo.path.join("f.txt").writeFile("v2");
        repo.add(repo.path.join("f.txt"));
        repo.commit("second");
        immutable second = repo.getCurrCommit;

        repo.tryRevParse("HEAD").shouldEqual(second);
        repo.tryRevParse("17.0.1.0.0").shouldEqual(first);
        repo.tryRevParse(first).shouldEqual(first);
        repo.tryRevParse("no-such-ref").shouldEqual("");

        repo.isAncestor(first, second).shouldBeTrue;
        repo.isAncestor(second, first).shouldBeFalse;
        // A commit is its own ancestor.
        repo.isAncestor(first, first).shouldBeTrue;
        // Tag spelling works as either side.
        repo.isAncestor("17.0.1.0.0", "HEAD").shouldBeTrue;
        // Unresolvable refs answer false, not an error.
        repo.isAncestor("no-such-ref", "HEAD").shouldBeFalse;
        repo.isAncestor("HEAD", "no-such-ref").shouldBeFalse;
    }

    /** Fetch remote 'origin'
      *
      * Params:
      *     prune    = remove remote-tracking refs that no longer exist on the
      *                remote (`--prune`). Without it, deleted remote branches
      *                linger in the local remote-tracking refs.
      *     all_tags = fetch all tags, including tags outside the fetched
      *                history that tag auto-following would miss (`--tags`).
      *                Combined with prune, also removes local tags deleted on
      *                the remote (`--prune-tags`).
      **/
    void fetchOrigin(in bool prune = false, in bool all_tags = false) const {
        auto cmd = gitCmd.withArgs("fetch", "origin");
        if (prune)
            cmd.addArgs("--prune");
        if (all_tags)
            cmd.addArgs("--tags");
        // --prune-tags is only valid together with --prune, and only
        // meaningful when tags are fetched.
        if (prune && all_tags)
            cmd.addArgs("--prune-tags");
        cmd.execute().ensureStatus(true);
    }

    /// ditto — fetch only `branch`. Note that with a branch refspec git
    /// applies `--prune` only within that refspec, so unrelated stale
    /// remote-tracking branches are not cleaned by this overload.
    void fetchOrigin(
            in string branch,
            in bool prune = false,
            in bool all_tags = false) const {
        auto cmd = gitCmd.withArgs("fetch", "origin", branch);
        if (prune)
            cmd.addArgs("--prune");
        if (all_tags)
            cmd.addArgs("--tags");
        if (prune && all_tags)
            cmd.addArgs("--prune-tags");
        cmd.execute().ensureStatus(true);
    }

    /** Fetch a specific tag from origin into the local repo.
      *
      * Uses an explicit refspec so it works reliably in single-branch clones
      * where the default fetch config only covers one branch and tags are not
      * automatically mirrored.
      **/
    void fetchTag(in string tag_name) const {
        immutable refspec = "refs/tags/%s:refs/tags/%s".format(tag_name, tag_name);
        gitCmd
            .withArgs("fetch", "origin", refspec)
            .execute()
            .ensureStatus(true);
    }

    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;
        import std.algorithm: canFind;

        auto root = createTempPath;
        scope(exit) root.remove();

        // Create a bare remote, a source repo with a tag, push both branch and tag.
        auto remote_path = root.join("remote.git");
        Process("git").withArgs("init", "--bare", remote_path.toString).execute.ensureOk(true);

        auto src_path = root.join("source");
        auto src = GitRepository.initialize(src_path);
        src_path.join("file.txt").writeFile("v1");
        src.add(src_path.join("file.txt"));
        src.commit("initial");
        src.remoteAdd("origin", remote_path.toString);
        src.gitCmd.withArgs("push", "-u", "origin", "HEAD").execute.ensureOk(true);
        src.setTag("17.0.1.0.0");
        src.pushTag("17.0.1.0.0");

        // Clone with --single-branch --no-tags — tags are NOT fetched automatically.
        auto clone_path = root.join("clone");
        Process("git")
            .withArgs("clone", "--single-branch", "--no-tags", remote_path.toString, clone_path.toString)
            .execute.ensureOk(true);
        auto clone = new GitRepository(clone_path);

        clone.listLocalTags().canFind("17.0.1.0.0").shouldBeFalse;

        // listRemoteTags resolves the remote by name (credentials/env via
        // gitCmd, no URL in argv) and sees tags that are not present locally.
        clone.listRemoteTags().canFind("17.0.1.0.0").shouldBeTrue;

        // fetchTag must bring the tag in via explicit refspec.
        clone.fetchTag("17.0.1.0.0");

        clone.listLocalTags().canFind("17.0.1.0.0").shouldBeTrue;
    }

    /// Test hasRemoteBranch + checkoutTrackingBranch
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        // Bare remote + source repo; push the default branch, then a hotfix branch.
        auto remote_path = root.join("remote.git");
        Process("git").withArgs("init", "--bare", remote_path.toString).execute.ensureOk(true);

        auto src_path = root.join("source");
        auto src = GitRepository.initialize(src_path);
        src_path.join("file.txt").writeFile("v1");
        src.add(src_path.join("file.txt"));
        src.commit("initial");
        src.remoteAdd("origin", remote_path.toString);
        src.gitCmd.withArgs("push", "-u", "origin", "HEAD").execute.ensureOk(true);

        src.createBranch("hotfix/18.0.1.0.x");
        src.gitCmd.withArgs("push", "-u", "origin", "hotfix/18.0.1.0.x").execute.ensureOk(true);

        // Single-branch clone: only the default branch is tracked locally; the
        // hotfix branch exists on the remote but not in the clone.
        auto clone_path = root.join("clone");
        Process("git")
            .withArgs("clone", "--single-branch", remote_path.toString, clone_path.toString)
            .execute.ensureOk(true);
        auto clone = new GitRepository(clone_path);

        clone.hasLocalBranch("hotfix/18.0.1.0.x").shouldBeFalse;
        clone.hasRemoteBranch("hotfix/18.0.1.0.x").shouldBeTrue;
        clone.hasRemoteBranch("hotfix/99.0.1.0.x").shouldBeFalse;

        // checkoutTrackingBranch creates the branch locally and switches to it.
        clone.checkoutTrackingBranch("hotfix/18.0.1.0.x");
        clone.hasLocalBranch("hotfix/18.0.1.0.x").shouldBeTrue;
        clone.getCurrBranch().get.should == "hotfix/18.0.1.0.x";
    }

    /// Test listRemoteBranches, listTags, resetBranchToRemote and
    /// fetchOrigin prune/all_tags flags.
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;
        import odood.git: gitListRemoteBranches;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto remote_path = root.join("remote.git");
        Process("git").withArgs("init", "--bare", remote_path.toString).execute.ensureOk(true);

        auto src_path = root.join("source");
        auto src = GitRepository.initialize(src_path);
        src_path.join("file.txt").writeFile("v1");
        src.add(src_path.join("file.txt"));
        src.commit("initial");
        src.remoteAdd("origin", remote_path.toString);
        src.gitCmd.withArgs("push", "-u", "origin", "HEAD").execute.ensureOk(true);
        immutable default_branch = src.getCurrBranch.get;
        immutable sha_default = src.getCurrCommit;

        // Feature branch with an extra commit.
        src.createBranch("feature/x");
        src_path.join("feature.txt").writeFile("f");
        src.add(src_path.join("feature.txt"));
        src.commit("feature commit");
        immutable sha_feature = src.getCurrCommit;
        src.gitCmd.withArgs("push", "-u", "origin", "feature/x").execute.ensureOk(true);
        src.switchBranchTo(default_branch);

        // Annotated (setTag uses -a) and lightweight tags on the default
        // branch head: listTags must resolve BOTH to the tagged commit
        // (annotated tags peeled through the tag object).
        src.setTag("17.0.1.0.0");
        src.gitCmd.withArgs("tag", "light-tag").execute.ensureOk(true);
        src.pushTag("17.0.1.0.0");
        src.gitCmd.withArgs("push", "origin", "light-tag").execute.ensureOk(true);

        auto tags = src.listTags();
        tags.canFind(GitTag("17.0.1.0.0", sha_default)).shouldBeTrue;
        tags.canFind(GitTag("light-tag", sha_default)).shouldBeTrue;

        // Branch enumeration: live via the repo method and via the free
        // function on a raw URL.
        auto clone_path = root.join("clone");
        Process("git")
            .withArgs("clone", remote_path.toString, clone_path.toString)
            .execute.ensureOk(true);
        auto clone = new GitRepository(clone_path);

        clone.listRemoteBranches().canFind(default_branch).shouldBeTrue;
        clone.listRemoteBranches().canFind("feature/x").shouldBeTrue;
        gitListRemoteBranches(remote_path.toString).canFind("feature/x").shouldBeTrue;

        // resetBranchToRemote creates a missing local branch...
        clone.hasLocalBranch("feature/x").shouldBeFalse;
        clone.resetBranchToRemote("feature/x");
        clone.getCurrBranch.get.should == "feature/x";
        clone.getCurrCommit.should == sha_feature;

        // ...and hard-resets a diverged one back to the remote state.
        clone_path.join("local.txt").writeFile("local");
        clone.add(clone_path.join("local.txt"));
        clone.commit("local-only commit");
        clone.getCurrCommit.shouldNotEqual(sha_feature);
        clone.resetBranchToRemote("feature/x");
        clone.getCurrCommit.should == sha_feature;

        // fetchOrigin(prune) removes remote-tracking refs of branches deleted
        // on the remote; without prune they linger.
        src.gitCmd.withArgs("push", "origin", "--delete", "feature/x").execute.ensureOk(true);
        auto has_tracking_ref = () => clone.gitCmd
            .withArgs("show-ref", "--verify", "--quiet", "refs/remotes/origin/feature/x")
            .withFlag(std.process.Config.stderrPassThrough)
            .execute.isOk;
        clone.fetchOrigin();
        has_tracking_ref().shouldBeTrue;
        clone.fetchOrigin(prune: true);
        has_tracking_ref().shouldBeFalse;
        // The live listing reflects the deletion immediately.
        clone.listRemoteBranches().canFind("feature/x").shouldBeFalse;

        // fetchOrigin(all_tags) brings in tags a --no-tags clone lacks.
        auto clone2_path = root.join("clone2");
        Process("git")
            .withArgs("clone", "--single-branch", "--no-tags", remote_path.toString, clone2_path.toString)
            .execute.ensureOk(true);
        auto clone2 = new GitRepository(clone2_path);
        clone2.listLocalTags().length.should == 0;
        clone2.fetchOrigin(all_tags: true);
        clone2.listLocalTags().canFind("17.0.1.0.0").shouldBeTrue;
        clone2.listLocalTags().canFind("light-tag").shouldBeTrue;
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

    /** Register remote `name` at `url` (`git remote add`) — for repositories
      * created locally (e.g. assembly bootstrap) rather than cloned.
      **/
    void remoteAdd(in string name, in string url) const {
        gitCmd
            .withArgs("remote", "add", name, url)
            .withFlag(std.process.Config.stderrPassThrough)
            .execute
            .ensureOk("Cannot add remote '%s' at '%s'".format(name, url), true);
    }

    /// ditto. Uses the clone-ready URL form (credentials included).
    void remoteAdd(in string name, in GitURL url) const {
        remoteAdd(name, url.toUrl);
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

    /** Switch repo to an existing branch.
      **/
    void switchBranchTo(in string branch_name) const {
        gitCmd
            .withArgs("checkout", branch_name)
            .execute()
            .ensureStatus(true);
    }

    /** Create a new branch and switch to it.
      *
      * When start_point is null (default), the branch is created from the
      * current HEAD. When provided, the branch starts at that ref (tag,
      * commit SHA, or branch name).
      *
      * Equivalent to: git checkout -b <branch_name> [start_point]
      **/
    void createBranch(in string branch_name, in string start_point = null) const {
        auto cmd = gitCmd.withArgs("checkout", "-b", branch_name);
        if (start_point !is null)
            cmd.addArgs(start_point);
        cmd.execute().ensureStatus(true);
    }

    /** Create branch `branch_name` at `start_point` and switch to it,
      * resetting the branch to `start_point` if it already exists.
      *
      * The create-or-reset counterpart of `createBranch` (which refuses to
      * touch an existing branch). DESTRUCTIVE for an existing branch: its
      * pointer is moved to `start_point`, so commits not reachable from
      * there are discarded (same caveat as `resetBranchToRemote`, which is
      * built on this method).
      *
      * When start_point is null (default), a missing branch is created from
      * the current HEAD and an existing one is reset to the current HEAD.
      *
      * Equivalent to: git checkout -B <branch_name> [start_point]
      **/
    void checkoutBranchAt(in string branch_name, in string start_point = null) const {
        auto cmd = gitCmd.withArgs("checkout", "-B", branch_name);
        if (start_point !is null)
            cmd.addArgs(start_point);
        cmd.execute().ensureStatus(true);
    }

    /// Test checkoutBranchAt (create-or-reset)
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto repo = GitRepository.initialize(root.join("repo"));
        repo.path.join("f.txt").writeFile("v1");
        repo.add(repo.path.join("f.txt"));
        repo.commit("initial");
        immutable first = repo.getCurrCommit;
        immutable main_branch = repo.getCurrBranch.get;

        repo.path.join("f.txt").writeFile("v2");
        repo.add(repo.path.join("f.txt"));
        repo.commit("second");
        immutable second = repo.getCurrCommit;

        // Creates a missing branch (at HEAD when no start point is given).
        repo.hasLocalBranch("work").shouldBeFalse;
        repo.checkoutBranchAt("work");
        repo.getCurrBranch.get.should == "work";
        repo.getCurrCommit.should == second;

        // createBranch (-b) refuses to touch an existing branch...
        repo.createBranch("work").shouldThrow;
        // ...while checkoutBranchAt resets it to the given start point.
        repo.checkoutBranchAt("work", first);
        repo.getCurrBranch.get.should == "work";
        repo.getCurrCommit.should == first;

        // Other branches are untouched by the reset.
        repo.switchBranchTo(main_branch);
        repo.getCurrCommit.should == second;
    }

    /** Check whether `remote` has a branch named `name`.
      *
      * Queries the remote directly via `git ls-remote`, so the result does not
      * depend on what has been fetched locally (works in single-branch clones).
      * Returns false when the remote is unreachable or has no such branch.
      **/
    bool hasRemoteBranch(in string name, in string remote = "origin") const {
        return this.remote(remote).hasBranch(name);
    }

    /** List all branch names available on the given remote.
      *
      * Queries the remote directly via `git ls-remote --heads` (like
      * `hasRemoteBranch` and `listRemoteTags`), so the result is live remote
      * state — it does not depend on what has been fetched, and never
      * contains stale entries for branches deleted on the remote. Uses the
      * remote NAME (not a resolved URL), so the repository's credential
      * helper and env apply and no credentials leak into process argv.
      **/
    string[] listRemoteBranches(in string remote = "origin") const {
        return this.remote(remote).listBranches();
    }

    /** Create a local branch tracking `remote`'s branch of the same name and
      * switch to it.
      *
      * Fetches the branch explicitly first (with a refspec that creates the
      * remote-tracking ref) so it works in single-branch clones where the
      * default fetch config would not cover it.
      *
      * Equivalent to:
      *   git fetch <remote> <name>:refs/remotes/<remote>/<name>
      *   git checkout -b <name> <remote>/<name>
      **/
    void checkoutTrackingBranch(in string name, in string remote = "origin") const {
        gitCmd
            .withArgs(
                "fetch", remote,
                "%s:refs/remotes/%s/%s".format(name, remote, name))
            .execute
            .ensureStatus(true);
        gitCmd
            .withArgs("checkout", "-b", name, "%s/%s".format(remote, name))
            .execute
            .ensureStatus(true);
    }

    /** Reset local branch `name` to match `remote`'s branch of the same name
      * and switch to it: create the branch if it does not exist, hard-move it
      * to the remote state if it does. The idempotent "make local match
      * remote" that `switchBranchTo` (does not create) and
      * `checkoutTrackingBranch` (does not reset an existing branch) do not
      * cover.
      *
      * DESTRUCTIVE: local commits on `name` that are not on the remote branch
      * are discarded (the branch pointer is moved and the worktree updated).
      * Local uncommitted changes are carried over by git where possible and
      * abort the checkout otherwise — callers that need a pristine result
      * should check `status.isClean` first.
      *
      * The branch is fetched explicitly first (same refspec as
      * `checkoutTrackingBranch`), so it reflects the actual remote state and
      * works in single-branch clones.
      *
      * Equivalent to:
      *   git fetch <remote> <name>:refs/remotes/<remote>/<name>
      *   git checkout -B <name> <remote>/<name>
      **/
    void resetBranchToRemote(in string name, in string remote = "origin") const {
        gitCmd
            .withArgs(
                "fetch", "--force", remote,
                "%s:refs/remotes/%s/%s".format(name, remote, name))
            .execute
            .ensureStatus(true);
        checkoutBranchAt(name, "%s/%s".format(remote, name));
    }

    /** Merge `merge_ref` into the current branch.
      *
      * A conflict is an expected outcome, not an exception: the method
      * returns false on it, and `abort_on_conflict` selects the tree state
      * left behind.
      *
      * Params:
      *     merge_ref = ref to merge (branch, tag, or commit). Must resolve
      *         in this repository — an unresolvable ref throws instead of
      *         being reported as a conflict.
      *     no_ff = always create a merge commit instead of fast-forwarding
      *         (`--no-ff`). Rejected in combination with `squash`.
      *     no_commit = stage the merge result without committing
      *         (`--no-commit`) — the caller reviews and commits.
      *     squash = stage the cumulative diff of `merge_ref` without
      *         committing and without recording a merge (`--squash`) — the
      *         caller commits it as ONE commit.
      *     abort_on_conflict = on conflict, restore a clean tree via
      *         `git reset --merge` (works for both regular merges and
      *         `--squash`, which writes no MERGE_HEAD, making `merge
      *         --abort` unavailable). DESTRUCTIVE to staged state — callers
      *         using it should start from a clean tree. When false,
      *         conflicts are left in place for manual resolution.
      *
      * Returns:
      *     true when the merge succeeded — including "nothing to do": after
      *     a `no_commit`/`squash` merge, true with
      *     `status().hasStagedChanges == false` means `merge_ref` carried no
      *     net change. false on conflict.
      **/
    bool merge(
            in string merge_ref,
            in bool no_ff = false,
            in bool no_commit = false,
            in bool squash = false,
            in bool abort_on_conflict = false) const {
        enforce!OdoodException(
            !(squash && no_ff),
            "Cannot merge with both squash and no_ff: " ~
            "git rejects --squash together with --no-ff.");
        enforce!OdoodException(
            !tryRevParse(merge_ref).empty,
            "Cannot merge '%s': it does not resolve to a commit in this repository.".format(
                merge_ref));

        auto cmd = gitCmd.withArgs("merge");
        if (no_ff) cmd.addArgs("--no-ff");
        if (no_commit) cmd.addArgs("--no-commit");
        if (squash) cmd.addArgs("--squash");
        cmd.addArgs(merge_ref);
        if (cmd.execute.isOk)
            return true;

        if (abort_on_conflict)
            // Best-effort: cleanup must not mask the merge outcome.
            gitCmd.withArgs("reset", "--merge").execute();
        return false;
    }

    /// Test merge: clean/ff, no_commit, squash, conflict policies, bad args
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto repo = GitRepository.initialize(root.join("repo"));
        repo.path.join("f.txt").writeFile("base\n");
        repo.add(repo.path.join("f.txt"));
        repo.commit("initial");
        immutable main_branch = repo.getCurrBranch.get;
        immutable initial = repo.getCurrCommit;

        // Feature branch with a non-conflicting change (separate file).
        repo.createBranch("feature");
        repo.path.join("feature.txt").writeFile("feature\n");
        repo.add(repo.path.join("feature.txt"));
        repo.commit("feature");
        immutable feature_sha = repo.getCurrCommit;
        repo.switchBranchTo(main_branch);

        // Invalid combination and unresolvable ref throw (not "conflict").
        repo.merge("feature", squash: true, no_ff: true)
            .shouldThrow!OdoodException;
        repo.merge("no-such-ref").shouldThrow!OdoodException;

        // no_commit merge: stages the result, creates no commit.
        repo.merge("feature", no_ff: true, no_commit: true).shouldBeTrue;
        repo.getCurrCommit.should == initial;
        repo.status.hasStagedChanges.shouldBeTrue;
        repo.gitCmd.withArgs("reset", "--merge").execute.ensureOk(true);

        // Plain merge fast-forwards when possible.
        repo.merge("feature").shouldBeTrue;
        repo.getCurrCommit.should == feature_sha;

        // Prepare a conflict: same line changed on both branches.
        repo.createBranch("conflicting");
        repo.path.join("f.txt").writeFile("theirs\n");
        repo.add(repo.path.join("f.txt"));
        repo.commit("theirs");
        repo.switchBranchTo(main_branch);
        repo.path.join("f.txt").writeFile("ours\n");
        repo.add(repo.path.join("f.txt"));
        repo.commit("ours");
        immutable ours_sha = repo.getCurrCommit;

        // Conflict without cleanup: false, conflicts left for manual resolution.
        repo.merge("conflicting").shouldBeFalse;
        repo.status.hasConflicts.shouldBeTrue;
        repo.gitCmd.withArgs("merge", "--abort").execute.ensureOk(true);

        // Conflict with cleanup: false, tree restored clean, HEAD unmoved.
        repo.merge("conflicting", abort_on_conflict: true).shouldBeFalse;
        repo.status.isClean.shouldBeTrue;
        repo.getCurrCommit.should == ours_sha;

        // Squash of a conflicting branch with cleanup behaves the same.
        repo.merge("conflicting", squash: true, abort_on_conflict: true)
            .shouldBeFalse;
        repo.status.isClean.shouldBeTrue;

        // Squash of a clean branch: stages the diff, HEAD unmoved.
        repo.createBranch("sq");
        repo.path.join("sq.txt").writeFile("sq\n");
        repo.add(repo.path.join("sq.txt"));
        repo.commit("sq change");
        repo.switchBranchTo(main_branch);
        repo.merge("sq", squash: true).shouldBeTrue;
        repo.getCurrCommit.should == ours_sha;
        repo.status.hasStagedChanges.shouldBeTrue;
        repo.commit("squashed");
        repo.path.join("sq.txt").exists.shouldBeTrue;
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

    /** List all tag names visible on the given remote.
      *
      * Runs `git ls-remote` inside the repository using the remote NAME (not a
      * resolved URL), so the repository's configured credential helper and its
      * env (`_env`, which may carry access tokens) apply — consistent with
      * every other method here — and no credentials embedded in a remote URL
      * leak into the process argv.
      **/
    string[] listRemoteTags(in string remote = "origin") const {
        return this.remote(remote).listTags();
    }

    /** Live query interface for this repository's configured remote (by
      * NAME — the repository's credential helper and env apply). See
      * `GitRemote`.
      **/
    GitRemote remote(in string remote_name = "origin") const {
        return GitRemote.of(this, remote_name);
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

    /** List refs matching `pattern` — e.g. `refs/tags` or
      * `refs/remotes/origin` — in one `for-each-ref` call, without a
      * checkout. See `GitRef` for the reported fields.
      *
      * Reflects LOCAL refs: remote-tracking refs and tags are only as fresh
      * as the last fetch (unlike the live `ls-remote`-based queries such as
      * `listRemoteBranches`/`listRemoteTags`).
      **/
    GitRef[] listRefs(in string pattern) const {
        auto output = gitCmd
            .withArgs("for-each-ref", pattern, "--format=" ~ GitRef.FORMAT)
            .execute
            .ensureOk(true)
            .output;
        GitRef[] res;
        foreach(line; output.splitLines) {
            auto r = GitRef.parse(line);
            if (!r.isNull)
                res ~= r.get;
        }
        return res;
    }

    /** Last commit of every branch of `remote`, read from its
      * remote-tracking refs in one call, no checkout. Requires a prior
      * fetch. Names are bare branch names; the `<remote>/HEAD` symref is
      * excluded.
      **/
    GitRef[] branchHeads(in string remote = "origin") const {
        GitRef[] res;
        immutable prefix = remote ~ "/";
        foreach(r; listRefs("refs/remotes/" ~ remote)) {
            // The <remote>/HEAD symref is not a branch; refname:short
            // renders it as just "<remote>" (a real branch named like the
            // remote renders "<remote>/<name>", so it is not shadowed).
            if (r.name == remote || r.name == prefix ~ "HEAD")
                continue;
            r.name = r.name.chompPrefix(prefix);
            res ~= r;
        }
        return res;
    }

    /** List all local tags together with the commit each points at.
      *
      * Annotated tags are peeled to the tagged commit; for lightweight tags
      * the ref itself is the commit. See `GitTag`. For tag dates and
      * messages, use `listRefs("refs/tags")` directly.
      **/
    GitTag[] listTags() const {
        GitTag[] res;
        foreach(r; listRefs("refs/tags"))
            res ~= GitTag(r.name, r.commit_sha);
        return res;
    }

    /// Test listRefs + branchHeads on a real repository
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto remote_path = root.join("remote.git");
        Process("git").withArgs("init", "--bare", remote_path.toString).execute.ensureOk(true);

        auto src_path = root.join("source");
        auto src = GitRepository.initialize(src_path);
        src_path.join("file.txt").writeFile("v1");
        src.add(src_path.join("file.txt"));
        src.commit("initial commit");
        src.remoteAdd("origin", remote_path.toString);
        src.gitCmd.withArgs("push", "-u", "origin", "HEAD").execute.ensureOk(true);
        immutable default_branch = src.getCurrBranch.get;
        immutable sha_initial = src.getCurrCommit;

        src.setTag("17.0.1.0.0", "Release 17.0.1.0.0");

        src.createBranch("feature/x");
        src_path.join("f2.txt").writeFile("f2");
        src.add(src_path.join("f2.txt"));
        src.commit("feature commit");
        immutable sha_feature = src.getCurrCommit;
        src.gitCmd.withArgs("push", "-u", "origin", "feature/x").execute.ensureOk(true);

        // Tags via listRefs: the annotated tag is peeled, date/author/subject
        // are populated from the tag object.
        auto tag_refs = src.listRefs("refs/tags");
        tag_refs.length.shouldEqual(1);
        with (tag_refs[0]) {
            name.shouldEqual("17.0.1.0.0");
            sha.shouldNotEqual(sha_initial);        // the tag object itself
            peeled_sha.shouldEqual(sha_initial);
            commit_sha.shouldEqual(sha_initial);
            (date > 0).shouldBeTrue;
            (author.length > 0).shouldBeTrue;       // tagger
            subject.shouldEqual("Release 17.0.1.0.0");
        }

        // listTags still agrees with listRefs after the refactor.
        src.listTags().shouldEqual([GitTag("17.0.1.0.0", sha_initial)]);

        // branchHeads on a fresh clone: bare names, HEAD symref excluded.
        auto clone_path = root.join("clone");
        Process("git")
            .withArgs("clone", remote_path.toString, clone_path.toString)
            .execute.ensureOk(true);
        auto clone = new GitRepository(clone_path);
        auto heads = clone.branchHeads();
        heads.length.shouldEqual(2);
        heads.map!(h => h.name).canFind(default_branch).shouldBeTrue;
        heads.map!(h => h.name).canFind("feature/x").shouldBeTrue;
        // The symbolic origin/HEAD is excluded (refname:short renders it
        // as just "origin").
        heads.map!(h => h.name).canFind("HEAD").shouldBeFalse;
        heads.map!(h => h.name).canFind("origin").shouldBeFalse;
        foreach(h; heads)
            if (h.name == "feature/x") {
                h.sha.shouldEqual(sha_feature);
                h.subject.shouldEqual("feature commit");
                (h.date > 0).shouldBeTrue;
                (h.author.length > 0).shouldBeTrue;
            }
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
        repo.remoteAdd("origin", remote_path.toString);
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

    /** List file and directory names directly under `dir` (non-recursive)
      * at the given ref.
      *
      * Works for both git refs and GIT_REF_WORKTREE (filesystem). Entries are
      * returned as paths relative to the repo root. Returns an empty array when
      * `dir` does not exist at that ref.
      **/
    Path[] listDir(in Path dir, in string rev) const {
        auto rel_dir = _makeRelPath(dir);
        if (rev == GIT_REF_WORKTREE) {
            auto abs_dir = _path.join(rel_dir);
            if (!abs_dir.exists || !abs_dir.isDir)
                return [];
            return abs_dir.walk  // default SpanMode.shallow — non-recursive
                .map!(p => rel_dir.join(p.baseName))
                .array;
        }

        // `git ls-tree --name-only <rev> -- <dir>/` lists the immediate children
        // of <dir> as repo-root-relative paths. A missing dir is not an error:
        // it yields empty output with status 0. A non-zero exit therefore means
        // a genuine git failure (invalid rev, broken repo, ...) and is raised.
        return gitCmd
            .withArgs(
                "ls-tree", "--name-only", rev, "--", "%s/".format(rel_dir))
            .withFlag(std.process.Config.stderrPassThrough)
            .execute
            .ensureOk(true)
            .output
            .strip
            .splitLines
            .filter!(l => l.length > 0)
            .map!(l => Path(l))
            .array;
    }

    /// ditto
    Path[] listDir(in Path dir) const {
        return listDir(dir, GIT_REF_WORKTREE);
    }

    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;
        import std.algorithm: sort, canFind;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto git_root = root.join("test-repo");
        auto repo = GitRepository.initialize(git_root);

        // Set up: addon_a/changelog/{changelog.1.0.0.md, changelog.1.1.0.md}
        git_root.join("addon_a", "changelog").mkdir(true);
        git_root.join("addon_a", "changelog", "changelog.1.0.0.md").writeFile("init");
        git_root.join("addon_a", "changelog", "changelog.1.1.0.md").writeFile("more");
        repo.add(git_root.join("addon_a"));
        repo.commit("Init");
        auto rev_v1 = repo.getCurrCommit();

        // Worktree listing (relative to repo root), order-independent.
        auto wt = repo.listDir(Path("addon_a/changelog"))
            .map!(p => p.toString).array;
        wt.length.should == 2;
        wt.canFind("addon_a/changelog/changelog.1.0.0.md").shouldBeTrue;
        wt.canFind("addon_a/changelog/changelog.1.1.0.md").shouldBeTrue;

        // Ref listing returns the same set.
        auto at_ref = repo.listDir(Path("addon_a/changelog"), rev_v1)
            .map!(p => p.toString).array;
        at_ref.length.should == 2;
        at_ref.canFind("addon_a/changelog/changelog.1.0.0.md").shouldBeTrue;

        // Add a third file in the worktree only; ref must not see it.
        git_root.join("addon_a", "changelog", "changelog.1.2.0.md").writeFile("new");
        repo.listDir(Path("addon_a/changelog")).length.should == 3;
        repo.listDir(Path("addon_a/changelog"), rev_v1).length.should == 2;

        // Missing directory → empty, for both worktree and ref.
        repo.listDir(Path("addon_a/nonexistent")).length.should == 0;
        repo.listDir(Path("addon_a/nonexistent"), rev_v1).length.should == 0;
    }

    /// Push current branch to a remote, optionally to a different branch name.
    /** Push the current branch to a remote.
      *
      * Params:
      *     branch_name = remote branch to push to (default: the current
      *         branch's own name).
      *     remote = remote to push to (default: origin).
      *     force_with_lease = overwrite the remote branch even when the
      *         push is not fast-forward (`--force-with-lease`) —
      *         DESTRUCTIVE to remote history. The lease guards against
      *         clobbering commits never seen locally: the push is refused
      *         when the remote branch does not match its local
      *         remote-tracking ref (i.e. the remote moved since the last
      *         fetch).
      **/
    void push(in string branch_name=null, in string remote="origin",
            in bool force_with_lease=false) const {
        auto current_branch = getCurrBranch();
        enforce!OdoodException(
            !current_branch.isNull,
            "Repository push operation is not allowed in detached tree mode");
        immutable target = branch_name ? branch_name : current_branch.get;

        auto cmd = gitCmd.withArgs("push");
        if (force_with_lease)
            cmd.addArgs("--force-with-lease");
        cmd.addArgs(remote, "%s:%s".format(current_branch.get, target));
        cmd.execute.ensureOk(
            "Cannot push changes to %s branch".format(target), true);
    }

    /// Test push: plain, non-ff rejection, and force_with_lease semantics
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;

        auto root = createTempPath;
        scope(exit) root.remove();

        auto remote_path = root.join("remote.git");
        Process("git").withArgs("init", "--bare", remote_path.toString).execute.ensureOk(true);

        auto src_path = root.join("source");
        auto src = GitRepository.initialize(src_path);
        src_path.join("f.txt").writeFile("v1");
        src.add(src_path.join("f.txt"));
        src.commit("initial");
        src.remoteAdd("origin", remote_path.toString);
        src.gitCmd.withArgs("push", "-u", "origin", "HEAD").execute.ensureOk(true);
        immutable branch = src.getCurrBranch.get;

        // Two independent clones.
        auto a_path = root.join("clone-a");
        Process("git").withArgs("clone", remote_path.toString, a_path.toString).execute.ensureOk(true);
        auto a = new GitRepository(a_path);
        auto b_path = root.join("clone-b");
        Process("git").withArgs("clone", remote_path.toString, b_path.toString).execute.ensureOk(true);
        auto b = new GitRepository(b_path);

        // B advances the remote.
        b_path.join("b.txt").writeFile("b");
        b.add(b_path.join("b.txt"));
        b.commit("b move");
        b.push();

        // A diverges locally.
        a_path.join("a.txt").writeFile("a");
        a.add(a_path.join("a.txt"));
        a.commit("a move");
        immutable sha_a = a.getCurrCommit;

        // Plain push: rejected (non fast-forward).
        a.push().shouldThrow;
        // Lease push with a STALE remote-tracking ref: still rejected — the
        // remote moved past what A last fetched, so the lease protects B's
        // commit from being clobbered unseen.
        a.push(force_with_lease: true).shouldThrow;
        // After a fetch the lease matches, so the overwrite is allowed.
        a.fetchOrigin();
        a.push(force_with_lease: true);
        a.tryRevParse("origin/" ~ branch).shouldEqual(sha_a);
    }

    /** Check git status and return minimal status information
      **/
    auto status() const {
        return GitStatus.parse(
            gitCmd
                .withArgs("status", "--untracked-files=all", "--porcelain", "--branch")
                .execute
                .ensureOk("Cannot get git status", true)
                .output);
    }
}
