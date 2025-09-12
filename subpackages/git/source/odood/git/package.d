module odood.git;

private import std.logger: infof;
private import std.exception: enforce;
private import std.format: format;
private import std.string: strip;

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
    // TODO: Think about adding ability to handle unexisting directories inside git root
    if (path.join(".git").exists)
        return true;

    const auto result = Process("git")
        .setArgs("rev-parse", "--git-dir")
        .setWorkDir(path)
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

    // Create repo
    auto git_root = root.join("test-repo");
    auto git_repo = GitRepository.initialize(git_root);

    // Check that git_repo is git repo
    git_root.isGitRepo.shouldBeTrue();

    git_root.join("some-test-dir", "some-subdir").mkdir(true);
    git_root.join("some-test-dir").isGitRepo.shouldBeTrue();
    git_root.join("some-test-dir", "some-subdir").isGitRepo.shouldBeTrue();

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
