module odood.git;

private import std.logger: infof;
private import std.exception: enforce;
private import std.format: format;

private import thepath: Path;

private import odood.exception: OdoodException;
private import theprocess: Process;

public import odood.git.url: GitURL;
public import odood.git.repository: GitRepository;


/// Parse git url for further processing
GitURL parseGitURL(in string url) {
    return GitURL(url);
}

/// Clone git repository to provided destination directory
GitRepository gitClone(
        in GitURL repo,
        in Path dest,
        in string branch,
        in bool single_branch=false) {
    enforce!OdoodException(
        dest.isValid,
        "Cannot clone repo %s! Destination path %s is invalid!".format(
            repo, dest));
    enforce!OdoodException(
        !dest.join(".git").exists,
        "It seems that repo %s already clonned to %s!".format(repo, dest));
    infof("Clonning repository (branch=%s, single_branch=%s): %s", branch, single_branch, repo);

    auto proc = Process("git")
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

