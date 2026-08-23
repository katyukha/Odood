module odood.git.remote;

private import std.typecons: Nullable, nullable;
private import std.string: strip, splitLines, startsWith, endsWith, chompPrefix, indexOf;
private static import std.process;

private import theprocess: Process;

private import odood.git: gitProcess;
private import odood.git.url: GitURL;
private import odood.git.refs: GitRef;
private import odood.git.repository: GitRepository;


/** Read-only query interface for a git remote, backed by `git ls-remote`.
  *
  * Every call is a live network round trip — results are never cached and
  * do not depend on local fetch state (unlike `GitRepository.listRefs`,
  * which reads local refs). The remote is addressed by URL or raw target
  * string (no clone needed), or by a repository's configured remote name
  * (`GitRemote.of`) — see the constructors.
  **/
struct GitRemote {
    private Process _base;   // preconfigured runner (env / workdir applied)
    private string _target;  // URL, local path, or remote name, as passed to git

    @disable this();

    private this(Process base, string target) {
        _base = base;
        _target = target;
    }

    /** Address the remote by URL. CI credential rewrites are applied
      * (like `gitClone`).
      **/
    this(in GitURL url, in string[string] env = null) {
        this(url.applyCIRewrites.toUrl, env);
    }

    /** Address the remote by a raw target string, passed to git verbatim
      * (URL, local path, scp form, ...). No CI rewrites.
      **/
    this(in string target, in string[string] env = null) {
        auto base = gitProcess;
        if (env !is null && env.length > 0)
            base = base.withEnv(env);
        this(base, target);
    }

    /** Address a repository's configured remote by name. Queries run
      * inside the repository, so its credential helper and env apply and no
      * credentials appear in the process argv.
      **/
    static GitRemote of(in GitRepository repo, in string remote = "origin") {
        return GitRemote(repo.gitCmd, remote);
    }

    /** Parse `git ls-remote` output ("<sha>\t<refname>" lines) into refs
      * with full refnames. Peeled entries (`<tag>^{}`) are folded into the
      * preceding tag's `peeled_sha`; `date`/`author`/`subject` are not
      * available remotely and stay empty. Symref headers (`ref: ...`) and
      * unparsable lines are skipped.
      **/
    private static GitRef[] parseLsRemote(in string output) {
        GitRef[] refs;
        foreach(line; output.splitLines) {
            if (line.startsWith("ref: "))
                continue;   // --symref header, not a ref entry
            auto tab = line.indexOf('\t');
            if (tab < 1)
                continue;
            auto sha = line[0 .. tab].strip;
            auto refname = line[tab + 1 .. $].strip;
            if (sha.length == 0 || refname.length == 0)
                continue;
            if (refname.endsWith("^{}")) {
                // Peeled entry: git prints it right after its tag's line.
                auto base_name = refname[0 .. $ - 3];
                if (refs.length > 0 && refs[$ - 1].name == base_name)
                    refs[$ - 1].peeled_sha = sha;
                continue;
            }
            refs ~= GitRef(name: refname, sha: sha);
        }
        return refs;
    }

    unittest {
        import unit_threaded.assertions;

        auto refs = GitRemote.parseLsRemote(
            "ref: refs/heads/main\tHEAD\n" ~
            "sha-head\tHEAD\n" ~
            "sha-head\trefs/heads/main\n" ~
            "sha-tag\trefs/tags/17.0.1.0.0\n" ~
            "sha-commit\trefs/tags/17.0.1.0.0^{}\n" ~
            "garbage line without tab\n");
        refs.length.shouldEqual(3);
        refs[0].name.shouldEqual("HEAD");
        refs[1].name.shouldEqual("refs/heads/main");
        refs[1].sha.shouldEqual("sha-head");
        refs[1].commit_sha.shouldEqual("sha-head");
        // Peeled entry folded into the annotated tag.
        refs[2].name.shouldEqual("refs/tags/17.0.1.0.0");
        refs[2].sha.shouldEqual("sha-tag");
        refs[2].peeled_sha.shouldEqual("sha-commit");
        refs[2].commit_sha.shouldEqual("sha-commit");

        GitRemote.parseLsRemote("").length.shouldEqual(0);
    }

    /** List refs on the remote, optionally narrowed by `ls-remote`
      * patterns (e.g. `"refs/tags/*"`). Names are full refnames; annotated
      * tags carry their peeled commit in `peeled_sha`. The remote
      * counterpart of `GitRepository.listRefs`.
      **/
    GitRef[] lsRemote(in string[] patterns...) const {
        return parseLsRemote(
            _base
                .withArgs(["ls-remote", _target] ~ patterns)
                .execute
                .ensureOk(true)
                .output);
    }

    /** List branch names on the remote (`refs/heads/` prefix stripped). **/
    string[] listBranches() const {
        string[] res;
        foreach(r; lsRemote("refs/heads/*"))
            res ~= r.name.chompPrefix("refs/heads/");
        return res;
    }

    /** List tag names on the remote (`refs/tags/` prefix stripped). **/
    string[] listTags() const {
        string[] res;
        foreach(r; lsRemote("refs/tags/*"))
            res ~= r.name.chompPrefix("refs/tags/");
        return res;
    }

    /** Check whether the remote has a branch named `name`. A probe, not a
      * query: an unreachable remote answers false instead of throwing
      * (which is why this does not go through `lsRemote`).
      **/
    bool hasBranch(in string name) const {
        return _base
            .withArgs(
                "ls-remote", "--heads", "--exit-code",
                _target, "refs/heads/" ~ name)
            .withFlag(std.process.Config.stderrPassThrough)
            .execute
            .isOk;
    }

    /** Name of the remote's default branch (its symbolic HEAD).
      *
      * Null when the remote has no symbolic HEAD pointing at a branch
      * (e.g. an empty repository); throws when the remote is unreachable.
      * The remote counterpart of `GitRepository.getCurrBranch`. Reads the
      * `ref: ...` symref header, which `parseLsRemote` skips — hence not
      * built on `lsRemote`.
      **/
    Nullable!string defaultBranch() const {
        enum prefix = "ref: refs/heads/";
        auto output = _base
            .withArgs("ls-remote", "--symref", _target, "HEAD")
            .execute
            .ensureOk(true)
            .output;
        foreach(line; output.splitLines)
            if (line.startsWith(prefix)) {
                auto rest = line[prefix.length .. $];
                auto tab = rest.indexOf('\t');
                if (tab > 0)
                    return rest[0 .. tab].strip.nullable;
            }
        return Nullable!string.init;
    }

    /** Resolve a ref name on the remote to the commit SHA it points at
      * (annotated tags peeled). Empty string when the ref does not exist.
      * The remote counterpart of `GitRepository.tryRevParse`. When several
      * refs match (e.g. a branch and a tag of the same name), the first one
      * as reported by git wins.
      **/
    string resolveRef(in string ref_name) const {
        // The "<ref>^{}" pattern is required to make git emit the peeled
        // entry for an annotated tag — plain patterns do not match it.
        auto refs = lsRemote(ref_name, ref_name ~ "^{}");
        if (refs.length == 0)
            return "";
        return refs[0].commit_sha;
    }

    /// Test GitRemote against a real (local, bare) remote
    unittest {
        import unit_threaded.assertions;
        import thepath.utils: createTempPath;
        import std.algorithm: canFind;

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
        immutable sha_initial = src.getCurrCommit;

        src.setTag("17.0.1.0.0", "Release 17.0.1.0.0");
        src.pushTag("17.0.1.0.0");

        // Raw-target form: a bare local path is accepted verbatim.
        auto remote = GitRemote(remote_path.toString);
        remote.listBranches.shouldEqual([branch]);
        remote.listTags.shouldEqual(["17.0.1.0.0"]);
        remote.hasBranch(branch).shouldBeTrue;
        remote.hasBranch("no-such-branch").shouldBeFalse;
        remote.defaultBranch.get.shouldEqual(branch);
        // Annotated tag resolves to the tagged COMMIT (peeled).
        remote.resolveRef("17.0.1.0.0").shouldEqual(sha_initial);
        remote.resolveRef(branch).shouldEqual(sha_initial);
        remote.resolveRef("no-such-ref").shouldEqual("");
        // Raw primitive reports full refnames.
        remote.lsRemote("refs/heads/*").length.shouldEqual(1);
        remote.lsRemote("refs/heads/*")[0].name.shouldEqual("refs/heads/" ~ branch);

        // Repo-scoped form: queries by remote NAME from inside the repo.
        auto by_name = GitRemote.of(src, "origin");
        by_name.listBranches.canFind(branch).shouldBeTrue;
        by_name.defaultBranch.get.shouldEqual(branch);

        // Empty remote: no branches, no default branch (null, not a throw).
        auto empty_path = root.join("empty.git");
        Process("git").withArgs("init", "--bare", empty_path.toString).execute.ensureOk(true);
        auto empty = GitRemote(empty_path.toString);
        empty.listBranches.length.shouldEqual(0);
        empty.defaultBranch.isNull.shouldBeTrue;
    }
}
