module odood.git;

private import std.logger: infof;
private import std.exception: enforce;
private import std.format: format;
private import std.string: strip, splitLines, startsWith, indexOf;
private import std.array: appender;

private import thepath: Path;

private import odood.exception: OdoodException;
private import theprocess: Process;

private import odood.git.url: redactCredentials, credentialValues;
public import odood.git.url: GitURL;
public import odood.git.repository: GitRepository;
public import odood.git.refs: GitTag, GitRef;
public import odood.git.status: GitStatus;
public import odood.git.remote: GitRemote;
public import odood.git.pull: GitPullStatus, GitPullResult;
public import odood.git.credential: gitCredentialEnv;

immutable string GIT_REF_WORKTREE = "-working-tree-";


/** Base runner for git CLI with locale pinned to C, so git's output and
  * error text is stable for parsing regardless of the user's locale.
  * `env` is applied on top, and can still override it. The password a
  * `gitCredentialEnv` map carries is masked in every text the process
  * renders.
  **/
package(odood) Process gitProcess(in string[string] env = null) {
    import odood.git.credential: GIT_CREDENTIAL_PASSWORD_ENV;

    auto res = Process("git").withEnv("LC_ALL", "C").withEnv(env);
    if (auto password = GIT_CREDENTIAL_PASSWORD_ENV in env)
        res.setMasked(*password);
    return res;
}

// The password of credentials passed through the env never shows in what a
// git process renders.
unittest {
    import std.algorithm: canFind;
    import unit_threaded.assertions;

    immutable text = gitProcess(
            gitCredentialEnv(GitURL("https://host.test/o/r"), "user", "TOKEN"))
        .withArgs("ls-remote", "https://host.test/o/r")
        .toString;
    text.canFind("TOKEN").shouldBeFalse;
    text.canFind("ODOOD_GIT_CREDENTIAL_PASSWORD").shouldBeTrue;
}


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

    immutable clone_url = repo.applyCIRewrites.toUrl;
    auto proc = gitProcess(env)
        .withMasked(credentialValues(clone_url))
        .withArgs("clone");
    if (branch)
        proc.addArgs("-b", branch);
    if (single_branch)
        proc.addArgs("--single-branch");
    proc.addArgs(clone_url, dest.toString);
    // An own message: it names the URL without its credentials, where the
    // default one lists every argument, with the credentials masked.
    proc.execute().ensureOk(
        "Cannot clone %s to %s".format(redactCredentials(clone_url), dest), true);
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

    const auto result = gitProcess
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


// A failing git command does not put the credentials of its URL into the
// exception message, which Odood logs; the message still names the remote.
unittest {
    import std.algorithm: canFind;
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;

    auto root = createTempPath;
    scope(exit) root.remove();

    // Nothing listens on the discard port, so git fails without a network.
    immutable url = "https://user:TOKEN@127.0.0.1:9/o/r";

    void checkMessage(in string msg) {
        msg.canFind("TOKEN").shouldBeFalse;
        msg.canFind("127.0.0.1:9/o/r").shouldBeTrue;
    }

    checkMessage(gitClone(GitURL(url), root.join("clone")).shouldThrow.msg);
    checkMessage(GitRemote(GitURL(url)).listTags.shouldThrow.msg);
    checkMessage(GitRemote(url).defaultBranch.shouldThrow.msg);

    auto repo = GitRepository.initialize(root.join("repo"));
    repo.remoteAdd("origin", GitURL(url));
    checkMessage(repo.remoteAdd("origin", GitURL(url)).shouldThrow.msg);
}


/** List all tag names available on a remote without cloning it.
  *
  * Wraps `git ls-remote --refs --tags <url>`.
  * Returns tag names only (the `refs/tags/` prefix is stripped).
  * Peeled dereference lines (`tag^{}`) are excluded by `--refs`.
  **/
string[] gitListRemoteTags(in string url, in string[string] env = null) {
    return GitRemote(url, env).listTags();
}

/** List all branch names available on a remote without cloning it.
  *
  * Wraps `git ls-remote --heads <url>`.
  * Returns branch names only (the `refs/heads/` prefix is stripped).
  **/
string[] gitListRemoteBranches(in string url, in string[string] env = null) {
    return GitRemote(url, env).listBranches();
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
        gitProcess
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
