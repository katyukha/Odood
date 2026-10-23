/// Helpers for locating and resolving Odood scripts (.py / .sql)
module odood.project.odoo.script;

private import std.algorithm: map, sort;
private import std.array: array;
private import std.file: SpanMode;
private import std.string: join;
private import std.format: format;
private import std.exception: enforce;
private import std.typecons: Nullable, nullable;

private import thepath: Path;

private import odood.project: Project;
private import odood.exception: OdoodException;
private import odood.git: isGitRepo, getGitTopLevel;


/** Resolve a script reference to an existing file path, auto-detecting the
  * repository enclosing the current working directory (if any) as the source
  * of `.odood-scripts/`.
  *
  * This is the convenience overload used by `odood script`. See the three-arg
  * overload for the resolution rules.
  *
  * Params:
  *     project = Odood project (provides the project-level `scripts/` directory)
  *     script = script reference: an absolute path, or a name/relative path
  *
  * Returns:
  *     Path to an existing script file.
  *
  * Throws:
  *     OdoodException if the script cannot be found.
  **/
Path resolveScriptPath(in Project project, in string script) {
    Nullable!Path repo_path;
    if (Path.current.isGitRepo)
        repo_path = getGitTopLevel(Path.current);
    return resolveScriptPath(project, script, repo_path);
}


/** Resolve a script reference to an existing file path.
  *
  * Used by `odood script` and the test runner's script hooks to let users refer
  * to a script by a short name instead of a full path.
  *
  * Absolute paths are used as is. Names and relative paths are searched (in
  * order) in:
  *   1. `<repo>/.odood-scripts/` — when a repository path is provided
  *      (repo-scoped scripts, kept under version control with the addons).
  *   2. `<project>/scripts/` — project-level scripts, not tied to any repo.
  *   3. the current working directory.
  *
  * Params:
  *     project = Odood project (provides the project-level `scripts/` directory)
  *     script = script reference: an absolute path, or a name/relative path
  *     repo_path = optional repository root to search `.odood-scripts/` in
  *
  * Returns:
  *     Path to an existing script file.
  *
  * Throws:
  *     OdoodException if the script cannot be found.
  **/
Path resolveScriptPath(
        in Project project,
        in string script,
        in Nullable!Path repo_path) {
    auto direct = Path(script);
    if (direct.isAbsolute) {
        enforce!OdoodException(
            direct.exists,
            "Script %s does not exist!".format(direct));
        return direct;
    }

    Path[] candidates;
    if (!repo_path.isNull)
        candidates ~= repo_path.get.join(".odood-scripts", script);
    candidates ~= project.project_root.join("scripts", script);
    candidates ~= Path.current.join(script);

    foreach(candidate; candidates)
        if (candidate.exists)
            return candidate;

    throw new OdoodException(
        "Cannot find script '%s'. Searched: %s".format(
            script, candidates.map!(c => c.toString).join(", ")));
}


/// Script kinds runnable by `odood script` and the test-runner hooks.
enum ScriptType {
    py,
    sql,
}


/** Directory a script was found in. The order of the members is the order
  * names are resolved in, thus an earlier source shadows a later one.
  **/
enum ScriptSource {
    repository,  /// <repo>/.odood-scripts/
    project,     /// <project>/scripts/
}


/// Single script found in one of the conventional script directories.
struct OdoodScript {
    /// File name, as it can be passed to `odood script py|sql`
    string name;

    /// Path to the script file
    Path path;

    ScriptType type;

    /// Hidden by a same-named script of an earlier source
    bool shadowed;
}


/// Scripts found in a single script directory.
struct ScriptGroup {
    ScriptSource source;

    /// Directory scanned; it does not necessarily exist
    Path directory;

    OdoodScript[] scripts;
}


/// Script type for a path, or null if the extension is not a supported one.
private Nullable!ScriptType scriptType(in Path path) {
    switch(path.extension) {
        case ".py":  return ScriptType.py.nullable;
        case ".sql": return ScriptType.sql.nullable;
        default:     return Nullable!ScriptType.init;
    }
}


/// Find supported scripts directly inside a directory, sorted by name.
private OdoodScript[] scanScriptDir(in Path directory) {
    // Symlinks are followed: a dangling one is neither a script nor a script
    // directory, and `isFile`/`isDir` would throw on it.
    if (!directory.exists(followSymlink: true) || !directory.isDir)
        return [];

    OdoodScript[] result;
    foreach(path; directory.walk(SpanMode.shallow)) {
        auto type = path.scriptType;
        if (type.isNull)
            continue;
        if (!path.exists(followSymlink: true) || !path.isFile)
            continue;
        result ~= OdoodScript(path.baseName, path, type.get, false);
    }
    return result.sort!((a, b) => a.name < b.name).array;
}


/** List the scripts, taking `.odood-scripts/` from the git repository
  * enclosing the current directory, if any.
  **/
ScriptGroup[] listScripts(in Project project) {
    Nullable!Path repo_path;
    if (Path.current.isGitRepo)
        repo_path = getGitTopLevel(Path.current);
    return listScripts(project, repo_path);
}


/** List the scripts `odood script py|sql` and the test-runner hooks find by
  * name: those in the conventional directories of `resolveScriptPath`. The
  * current directory is not listed, as it may hold unrelated Python files.
  *
  * Groups come in resolution order. A missing directory yields an empty
  * group, so callers can still show where scripts are looked for.
  *
  * Params:
  *     project = Odood project, providing the `scripts/` directory
  *     repo_path = repository root to scan `.odood-scripts/` in, if any
  *
  * Returns: one group per script directory.
  **/
ScriptGroup[] listScripts(in Project project, in Nullable!Path repo_path) {
    ScriptGroup[] groups;
    if (!repo_path.isNull) {
        auto directory = repo_path.get.join(".odood-scripts");
        groups ~= ScriptGroup(
            ScriptSource.repository, directory, scanScriptDir(directory));
    }

    auto project_dir = project.project_root.join("scripts");
    groups ~= ScriptGroup(
        ScriptSource.project, project_dir, scanScriptDir(project_dir));

    bool[string] seen;
    foreach(ref group; groups)
        foreach(ref script; group.scripts) {
            script.shadowed = (script.name in seen) !is null;
            seen[script.name] = true;
        }
    return groups;
}


unittest {
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;
    import std.algorithm: map;
    import std.array: array;
    import odood.utils.odoo.serie: OdooSerie;

    auto root = createTempPath;
    scope(exit) root.remove();

    auto project = new Project(root, OdooSerie(17));

    auto repo_path = root.join("repositories", "my-addons");
    auto repo_scripts = repo_path.join(".odood-scripts");
    repo_scripts.mkdir(true);
    repo_scripts.join("seed_demo.sql").writeFile("");
    repo_scripts.join("recompute_totals.py").writeFile("");
    // Neither a supported script type nor a file → both skipped.
    repo_scripts.join("README.md").writeFile("");
    repo_scripts.join("helpers").mkdir();
    // A dangling symlink is skipped, not an error
    version(Posix)
        root.join("gone.py").symlink(repo_scripts.join("dangling.py"));

    auto project_scripts = root.join("scripts");
    project_scripts.mkdir(true);
    project_scripts.join("recompute_totals.py").writeFile("");
    project_scripts.join("cleanup.sql").writeFile("");

    auto groups = listScripts(project, repo_path.nullable);
    groups.map!(g => g.source).array.should == [
        ScriptSource.repository, ScriptSource.project];

    groups[0].scripts.map!(s => s.name).array.should == [
        "recompute_totals.py", "seed_demo.sql"];
    groups[0].scripts.map!(s => s.type).array.should == [
        ScriptType.py, ScriptType.sql];
    groups[0].scripts.map!(s => s.shadowed).array.should == [false, false];

    // The repository's 'recompute_totals.py' shadows the project one.
    groups[1].scripts.map!(s => s.name).array.should == [
        "cleanup.sql", "recompute_totals.py"];
    groups[1].scripts.map!(s => s.shadowed).array.should == [false, true];

    // A scripts directory that does not resolve yields an empty group
    version(Posix) {
        repo_scripts.remove();
        root.join("gone").symlink(repo_scripts);
        listScripts(project, repo_path.nullable)[0].scripts.length.should == 0;
    }

    // A missing directory yields an empty group; no repository, no group.
    project_scripts.remove();
    auto no_repo_groups = listScripts(project, Nullable!Path.init);
    no_repo_groups.length.should == 1;
    no_repo_groups[0].source.should == ScriptSource.project;
    no_repo_groups[0].scripts.length.should == 0;
}
