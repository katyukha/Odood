module odood.git.status;

private import std.string: splitLines;
private import std.algorithm: canFind, startsWith;
private import std.regex: ctRegex, matchFirst;
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

    /** Parse the branch header line of `git status --porcelain --branch`
      * into the branch/tracking fields of `status`.
      *
      * The header has one of these forms:
      *
      *     ## main...origin/main [ahead 1, behind 2]
      *     ## 18.0...origin/18.0 [gone]
      *     ## 18.0
      *     ## HEAD (no branch)
      *     ## No commits yet on 18.0
      *
      * Note that a branch name may contain dots (Odoo branches are named
      * `18.0`, `17.0`, ...), thus the branch name cannot be matched as
      * "everything up to a dot". Git forbids `..` in ref names (see
      * `git check-ref-format`), thus the first `...` is unambiguously the
      * separator between the local and the remote branch.
      **/
    private static void parseHeader(in string line, ref GitStatus status) {
        /* Detached HEAD and unborn branch carry no tracking information.
         * They are matched separately, because they are not `<local>...<remote>`.
         */
        if (line.matchFirst(ctRegex!(r"^##\s+HEAD\s+\(no branch\)")))
            return;
        if (auto m = line.matchFirst(ctRegex!(r"^##\s+No commits yet on\s+(?P<local>\S+)"))) {
            status.localBranch = m["local"];
            return;
        }

        /* Anchored at the end of line, because otherwise the lazy `\S+?`
         * would match a single character: everything after it is optional.
         * The tracking part is captured as a whole, so that values we do not
         * parse (like `gone`) do not make the whole line unparsable.
         */
        auto m = line.matchFirst(ctRegex!(
            r"^##\s+(?P<local>\S+?)(?:\.\.\.(?P<remote>[^\s\[]+))?(?:\s+\[(?P<track>[^\]]*)\])?$"));
        if (!m)
            return;

        status.localBranch = m["local"];
        status.remoteBranch = m["remote"].length ? m["remote"] : null;

        if (m["track"].length) {
            if (auto ahead = m["track"].matchFirst(ctRegex!(r"ahead\s+(\d+)")))
                status.ahead = ahead[1].to!int;
            if (auto behind = m["track"].matchFirst(ctRegex!(r"behind\s+(\d+)")))
                status.behind = behind[1].to!int;
        }
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

        parseHeader(lines[0], status);

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

    /// Branch header: dotted names, missing upstream, detached, unborn.
    unittest {
        import unit_threaded.assertions;

        /* Branch names of Odoo repositories contain dots, and the tracking
         * counters must survive them, otherwise isDiverged always says "no".
         */
        with (GitStatus.parse("## 18.0...origin/18.0 [ahead 1, behind 2]\n")) {
            localBranch.shouldEqual("18.0");
            remoteBranch.shouldEqual("origin/18.0");
            ahead.shouldEqual(1);
            behind.shouldEqual(2);
            isDiverged.shouldBeTrue;
        }

        with (GitStatus.parse("## 18.0-fix-crash...origin/18.0-fix-crash\n")) {
            localBranch.shouldEqual("18.0-fix-crash");
            remoteBranch.shouldEqual("origin/18.0-fix-crash");
        }

        with (GitStatus.parse("## release/1.2.3...origin/release/1.2.3 [behind 3]\n")) {
            localBranch.shouldEqual("release/1.2.3");
            remoteBranch.shouldEqual("origin/release/1.2.3");
            ahead.shouldEqual(0);
            behind.shouldEqual(3);
            isDiverged.shouldBeFalse;
        }

        // Dotted branch without an upstream.
        with (GitStatus.parse("## 18.0\n")) {
            localBranch.shouldEqual("18.0");
            remoteBranch.shouldBeNull;
        }

        // Upstream is configured, but gone. Tracking text we do not parse
        // must not make the branch names unparsable.
        with (GitStatus.parse("## 18.0...origin/18.0 [gone]\n")) {
            localBranch.shouldEqual("18.0");
            remoteBranch.shouldEqual("origin/18.0");
            ahead.shouldEqual(0);
            behind.shouldEqual(0);
        }

        // Detached HEAD: no branch at all.
        with (GitStatus.parse("## HEAD (no branch)\nM  staged.txt\n")) {
            localBranch.shouldBeNull;
            remoteBranch.shouldBeNull;
            hasStagedChanges.shouldBeTrue;  // entries are still parsed
        }

        // Freshly initialized repository, before the first commit.
        with (GitStatus.parse("## No commits yet on 18.0\n?? new.txt\n")) {
            localBranch.shouldEqual("18.0");
            remoteBranch.shouldBeNull;
            hasUntracked.shouldBeTrue;
        }
    }
}
