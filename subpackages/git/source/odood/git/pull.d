module odood.git.pull;

private import std.exception: enforce;
private import std.format: format;

private import thepath: Path;

private import odood.exception: OdoodException;


/// Outcome of `GitRepository.pull`.
enum GitPullStatus {
    /** The branch was fast-forwarded to its upstream, or, with `ff_only`
      * off, the upstream was merged into it.
      **/
    updated,

    /// The upstream has no commits the branch lacks.
    upToDate,

    /** Uncommitted changes to tracked files, or unresolved conflicts.
      * Untracked files do not count: a fast-forward does not touch them,
      * and git refuses to overwrite one with an incoming file.
      **/
    uncommittedChanges,

    /// HEAD is not on a branch.
    detached,

    /// The branch has no upstream configured.
    noUpstream,

    /// The upstream branch does not exist on the remote.
    upstreamGone,

    /// Both the branch and its upstream have commits the other lacks.
    /// Reported with `ff_only` only.
    diverged,

    /// Merging the upstream (with `ff_only` off) conflicted; the merge was
    /// aborted.
    mergeConflict,

    /// Fetching from the remote failed.
    fetchFailed,
}


/// Result of `GitRepository.pull`.
struct GitPullResult {
    GitPullStatus status;

    /// Repository that was pulled.
    Path path;

    /// Current branch; null for a detached HEAD.
    string branch;

    /// Upstream of the branch, e.g. `origin/18.0`; null if there is none.
    string upstream;

    /// HEAD before and after the pull. Set only when status is `updated`.
    string fromCommit;
    string toCommit;  /// ditto

    /// Git's error message. Set only when status is `fetchFailed`.
    string error;

    /// The branch is at its upstream: it was updated or already up to date.
    bool isOk() const {
        return status == GitPullStatus.updated || status == GitPullStatus.upToDate;
    }

    /** Ensure the branch is at its upstream.
      *
      * Returns: this result, for chaining.
      * Throws: OdoodException naming the repository and the reason.
      **/
    GitPullResult ensureOk() const {
        enforce!OdoodException(
            isOk, "Cannot pull %s: %s".format(path, toString));
        return this;
    }

    /// The outcome in words, e.g. "branch 18.0 has diverged from origin/18.0".
    string toString() const {
        final switch(status) {
            case GitPullStatus.updated:
                return "updated %s..%s".format(fromCommit[0 .. 8], toCommit[0 .. 8]);
            case GitPullStatus.upToDate:
                return "already up to date";
            case GitPullStatus.uncommittedChanges:
                return "uncommitted changes";
            case GitPullStatus.detached:
                return "detached HEAD";
            case GitPullStatus.noUpstream:
                return "branch %s has no upstream".format(branch);
            case GitPullStatus.upstreamGone:
                return "upstream %s does not exist on the remote".format(upstream);
            case GitPullStatus.diverged:
                return "branch %s has diverged from %s".format(branch, upstream);
            case GitPullStatus.mergeConflict:
                return "merging %s into branch %s conflicts".format(upstream, branch);
            case GitPullStatus.fetchFailed:
                return "cannot fetch: %s".format(error);
        }
    }
}
