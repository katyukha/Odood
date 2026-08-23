module odood.git.refs;

private import std.typecons: Nullable, nullable;
private import std.array: split, join;
private import std.conv: to;


/** Tag together with the commit it points at.
  *
  * For annotated tags `sha` is the peeled (dereferenced) commit, not the tag
  * object itself; for lightweight tags it is the commit directly — so `sha`
  * always identifies the tagged commit regardless of the tag kind.
  **/
struct GitTag {
    string name;
    string sha;
}

/** One git ref as reported by `for-each-ref` (see `GitRepository.listRefs`).
  **/
struct GitRef {
    /// Short ref name (e.g. "origin/main", "17.0.1.0.0").
    string name;
    /// The object the ref points at (for an annotated tag: the tag object).
    string sha;
    /// For annotated tags: the tagged commit. Empty otherwise.
    string peeled_sha;
    /// Creation date as unix timestamp: committer date for commits,
    /// tagger date for annotated tags. 0 = unknown.
    long date = 0;
    /// Author of the commit, or tagger of an annotated tag. "" if unknown.
    string author;
    /// Subject line of the commit/tag message.
    string subject;

    /// The commit this ref ultimately points at (peeled for annotated tags).
    string commit_sha() const => peeled_sha.length > 0 ? peeled_sha : sha;

    /* %09 = tab. Control characters are forbidden in refnames, so tab is a
     * safe field separator; the subject (which MAY contain tabs) goes last,
     * so a tab inside it cannot shift the other columns.
     */
    package(odood) enum FORMAT =
        "%(refname:short)%09%(objectname)%09%(*objectname)%09" ~
        "%(creatordate:unix)%09%(authorname)%09%(taggername)%09%(subject)";

    /** Parse one line of `for-each-ref` output produced with `FORMAT`.
      *
      * Returns: null result for an unparsable line; an unparsable date
      *     yields 0.
      **/
    static Nullable!GitRef parse(in string line) {
        auto parts = line.split("\t");
        if (parts.length < 7 || parts[0].length == 0)
            return Nullable!GitRef.init;
        GitRef r;
        r.name = parts[0];
        r.sha = parts[1];
        r.peeled_sha = parts[2];
        try r.date = parts[3].to!long;
        catch (Exception) r.date = 0;
        // A commit has an author; an annotated tag has a tagger.
        r.author = parts[4].length > 0 ? parts[4] : parts[5];
        r.subject = parts[6 .. $].join("\t");
        return r.nullable;
    }

    unittest {
        import unit_threaded.assertions;

        // Branch head: commit → no peeled sha, author set, no tagger.
        with (GitRef.parse("origin/main\tsha-a\t\t1700000000\tAlice\t\tInitial commit").get) {
            name.shouldEqual("origin/main");
            sha.shouldEqual("sha-a");
            peeled_sha.shouldEqual("");
            commit_sha.shouldEqual("sha-a");
            date.shouldEqual(1700000000);
            author.shouldEqual("Alice");
            subject.shouldEqual("Initial commit");
        }

        // Annotated tag: peeled sha set, tagger set, no author; the subject
        // contains a tab that must survive (subject is the LAST field).
        with (GitRef.parse("17.0.1.0.0\tsha-tag\tsha-commit\t1700000001\t\tBob\tRelease\t17.0.1.0.0").get) {
            commit_sha.shouldEqual("sha-commit");       // peeled
            author.shouldEqual("Bob");                  // tagger fallback
            subject.shouldEqual("Release\t17.0.1.0.0"); // tab preserved
        }

        // Unparsable date yields 0 instead of throwing.
        GitRef.parse("t\ts\t\tnot-a-date\tA\t\tmsg").get.date.shouldEqual(0);

        // Unparsable lines yield a null result.
        GitRef.parse("broken line without tabs").isNull.shouldBeTrue;
        GitRef.parse("").isNull.shouldBeTrue;
    }
}
