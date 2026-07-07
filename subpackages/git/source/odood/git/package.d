module odood.git;

private import std.logger: infof;
private import std.exception: enforce;
private import std.format: format;
private import std.string: strip, splitLines, startsWith, indexOf;
private import std.array: appender;

private import thepath: Path;

private import odood.exception: OdoodException;
private import theprocess: Process;

public import odood.git.url: GitURL;
public import odood.git.repository: GitRepository;

immutable string GIT_REF_WORKTREE = "-working-tree-";


/// Parse git url for further processing
GitURL parseGitURL(in string url) {
    return GitURL(url);
}

/// Create git URL for a local repository. The path must be absolute.
GitURL parseGitURL(in Path path) {
    return GitURL(path);
}

/// Clone git repository to provided destination directory
GitRepository gitClone(
        in GitURL repo,
        in Path dest,
        in string branch=null,
        in bool single_branch=false,
        in string[string] env=null) {
    enforce!OdoodException(
        dest.isValid,
        "Cannot clone repo %s! Destination path %s is invalid!".format(
            repo, dest));
    enforce!OdoodException(
        !dest.join(".git").exists,
        "It seems that repo %s already clonned to %s!".format(repo, dest));
    infof("Clonning repository (branch=%s, single_branch=%s): %s", branch, single_branch, repo);

    auto proc = Process("git")
        .withEnv(env)
        .withArgs("clone");
    if (branch)
        proc.addArgs("-b", branch);
    if (single_branch)
        proc.addArgs("--single-branch");
    proc.addArgs(repo.applyCIRewrites.toUrl, dest.toString);
    proc.execute().ensureOk(true);
    return new GitRepository(dest);
}


/** Check if specified path is git repository
  **/
bool isGitRepo(in Path path) {
    // A non-existent path is not a git repository. Guard early: the worktree
    // fallback below runs `git` with `inWorkDir(path)`, which throws a
    // ProcessException ("failed to open working directory") for a missing
    // directory instead of reporting "not a repo".
    if (!path.exists)
        return false;

    if (path.join(".git").exists)
        return true;

    const auto result = Process("git")
        .withArgs("rev-parse", "--git-dir")
        .inWorkDir(path)
        .execute();
    if (result.status == 0)
        return true;

    return false;
}

///
unittest {
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;

    auto root = createTempPath;
    scope(exit) root.remove();

    // check if random dir is not git directory
    root.join("some-other-dir").mkdir(true);
    root.join("some-other-dir").isGitRepo.shouldBeFalse();

    // a non-existent path is not a git repo (must return false, not throw)
    root.join("does-not-exist").isGitRepo.shouldBeFalse();

    // Create repo
    auto git_root = root.join("test-repo");
    auto git_repo = GitRepository.initialize(git_root);

    // Check that git_repo is git repo
    git_root.isGitRepo.shouldBeTrue();

    git_root.join("some-test-dir", "some-subdir").mkdir(true);
    git_root.join("some-test-dir").isGitRepo.shouldBeTrue();
    git_root.join("some-test-dir", "some-subdir").isGitRepo.shouldBeTrue();

}


/** List all tag names available on a remote without cloning it.
  *
  * Wraps `git ls-remote --refs --tags <url>`.
  * Returns tag names only (the `refs/tags/` prefix is stripped).
  * Peeled dereference lines (`tag^{}`) are excluded by `--refs`.
  **/
string[] gitListRemoteTags(in string url, in string[string] env = null) {
    auto proc = Process("git")
        .withArgs("ls-remote", "--refs", "--tags", url);
    if (env !is null && env.length > 0)
        proc = proc.withEnv(env);
    return parseLsRemoteTags(proc.execute.ensureOk(true).output);
}

/** Parse `git ls-remote --refs --tags` output into bare tag names.
  *
  * Each line is "<sha>\trefs/tags/<tagname>"; the `refs/tags/` prefix is
  * stripped. Shared by `gitListRemoteTags` and `GitRepository.listRemoteTags`.
  **/
package(odood) string[] parseLsRemoteTags(in string output) {
    auto tags = appender!(string[]);
    foreach(line; output.splitLines) {
        auto tab = line.indexOf('\t');
        if (tab < 0) continue;
        auto refname = line[tab + 1 .. $];
        enum prefix = "refs/tags/";
        if (refname.startsWith(prefix))
            tags ~= refname[prefix.length .. $];
    }
    return tags.data;
}

///
unittest {
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;

    auto root = createTempPath;
    scope(exit) root.remove();

    // Create a repo with two tags and verify gitListRemoteTags returns them.
    auto repo_path = root.join("tagged-repo");
    auto repo = GitRepository.initialize(repo_path);

    repo_path.join("file.txt").writeFile("hello");
    repo.add(repo_path.join("file.txt"));
    repo.commit("initial commit");
    repo.setTag("16.0.1.0.0", "First release");

    repo_path.join("file.txt").writeFile("world");
    repo.add(repo_path.join("file.txt"));
    repo.commit("second commit");
    repo.setTag("16.0.1.0.1", "Second release");

    import std.algorithm: canFind;
    auto tags = gitListRemoteTags(repo_path.toString);
    tags.canFind("16.0.1.0.0").shouldBeTrue;
    tags.canFind("16.0.1.0.1").shouldBeTrue;
    tags.length.should == 2;
}


/** Returns absolute path to repository root directory.

    Parametrs:
        path = any path inside repository
  **/
Path getGitTopLevel(in Path path) {
    enforce!OdoodException(
        path.isGitRepo,
        "Expected that %s is git repository".format(path));
    return Path(
        Process("git")
            .inWorkDir(path)
            .withArgs("rev-parse", "--show-toplevel")
            .execute
            .ensureOk(true)
            .output
            .strip
    );
}

///
unittest {
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;

    auto root = createTempPath;
    scope(exit) root.remove();

    // Attempt to get git root for random directory should fail
    root.join("some-other-dir").mkdir(true);
    root.join("some-other-dir").getGitTopLevel.shouldThrow!OdoodException();

    // Create repo
    auto git_root = root.join("test-repo");
    auto git_repo = GitRepository.initialize(git_root);

    // Check that git_repo is git repo
    git_root.getGitTopLevel.realPath.should == git_root.realPath;

    git_root.join("some-test-dir", "some-subdir").mkdir(true);
    git_root.join("some-test-dir").getGitTopLevel.realPath.should == git_root.realPath;
    git_root.join("some-test-dir", "some-subdir").getGitTopLevel.realPath.should == git_root.realPath;
}
