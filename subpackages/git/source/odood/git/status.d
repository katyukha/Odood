module odood.git.status;

private import std.string: splitLines;
private import std.algorithm: canFind, startsWith;
private import std.regex: regex, matchFirst;
private import std.conv: to;


/** Representation of result of `git status` command.
  **/
struct GitStatus {
    /// Any tracked-file change, staged or not (conflicts excluded).
    bool hasChanges = false;
    /// Index differs from HEAD (staged, uncommitted changes).
    bool hasStagedChanges = false;
    /// Worktree differs from the index (unstaged modifications/deletions).
    bool hasUnstagedChanges = false;
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

    /** Parse the output of `git status --porcelain --branch`.
      *
      * Each entry line is `XY PATH`, where X is the status of the file in the
      * index (staged) and Y its status in the worktree relative to the index
      * (unstaged); `??` marks an untracked file and the conflict pairs (DD,
      * AU, UD, UA, DU, AA, UU) mark unmerged paths. Unparsable lines are
      * skipped.
      **/
    static GitStatus parse(in string output) {
        GitStatus status;
        auto lines = output.splitLines();
        if (lines.length == 0) return status;

        /* Header regex description
         * 1. (?P<local>[^\s\.]+) - local branch name
         * 2. (?:\.\.\.(?P<remote>[^\s\[]+))? - optional remote branch name (separated from local branch via '...)
         * 3. statistics ahead/behind that is used to check for diverged state
         *
         * Sample: ## main...origin/main [ahead 1, behind 2]
         */
        auto headerRegex = regex(r"^##\s+(?P<local>[^\s\.]+)(?:\.\.\.(?P<remote>[^\s\[]+))?(?:\s+\[(?:ahead\s+(?P<ahead>\d+))?(?:,\s+)?(?:behind\s+(?P<behind>\d+))?\])?");

        if (auto m = lines[0].matchFirst(headerRegex)) {
            status.localBranch = m["local"];
            status.remoteBranch = m["remote"].length ? m["remote"] : null;

            if (m["ahead"].length) status.ahead = m["ahead"].to!int;
            if (m["behind"].length) status.behind = m["behind"].to!int;
        }

        foreach (line; lines[1..$]) {
            if (line.length < 3)
                /* Minimal meaningful line is `XY PATH`, thus here we skip
                 * empty or unparsable lines.
                 */
                continue;
            if (["DD", "AU", "UD", "UA", "DU", "AA", "UU"].canFind(line[0 .. 2]))
                status.hasConflicts = true;
            else if (line.startsWith("??"))
                status.hasUntracked = true;
            else {
                // "M ", " M", "MM", "A ", "R ", ...
                status.hasChanges = true;
                if (line[0] != ' ')
                    status.hasStagedChanges = true;
                if (line[1] != ' ')
                    status.hasUnstagedChanges = true;
            }
        }
        return status;
    }

    unittest {
        import unit_threaded.assertions;

        // Clean repo on a tracked branch.
        with (GitStatus.parse("## main...origin/main\n")) {
            localBranch.shouldEqual("main");
            remoteBranch.shouldEqual("origin/main");
            isClean.shouldBeTrue;
            hasStagedChanges.shouldBeFalse;
            hasUnstagedChanges.shouldBeFalse;
        }

        // Diverged branch with every kind of entry at once.
        with (GitStatus.parse(
                "## main...origin/main [ahead 1, behind 2]\n" ~
                "M  staged.txt\n" ~
                " M unstaged.txt\n" ~
                "?? untracked.txt\n" ~
                "UU conflicted.txt\n")) {
            ahead.shouldEqual(1);
            behind.shouldEqual(2);
            isDiverged.shouldBeTrue;
            hasChanges.shouldBeTrue;
            hasStagedChanges.shouldBeTrue;
            hasUnstagedChanges.shouldBeTrue;
            hasUntracked.shouldBeTrue;
            hasConflicts.shouldBeTrue;
            isClean.shouldBeFalse;
        }

        // Staged only: index differs from HEAD, worktree matches the index.
        with (GitStatus.parse("## main\nA  new.txt\n")) {
            hasStagedChanges.shouldBeTrue;
            hasUnstagedChanges.shouldBeFalse;
            hasChanges.shouldBeTrue;
            remoteBranch.shouldBeNull;
        }

        // Unstaged only: worktree differs, nothing staged.
        with (GitStatus.parse("## main\n D deleted.txt\n")) {
            hasStagedChanges.shouldBeFalse;
            hasUnstagedChanges.shouldBeTrue;
        }

        // One file changed both in the index and on top of it in the worktree.
        with (GitStatus.parse("## main\nMM both.txt\n")) {
            hasStagedChanges.shouldBeTrue;
            hasUnstagedChanges.shouldBeTrue;
        }

        // A conflict alone is not a "change" (matches isClean semantics).
        with (GitStatus.parse("## main\nUU conflicted.txt\n")) {
            hasConflicts.shouldBeTrue;
            hasChanges.shouldBeFalse;
            hasStagedChanges.shouldBeFalse;
            hasUnstagedChanges.shouldBeFalse;
        }

        // Empty output parses to the default (clean) status.
        GitStatus.parse("").isClean.shouldBeTrue;
    }
}
