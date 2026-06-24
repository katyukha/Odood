/// Helpers for locating and resolving Odood scripts (.py / .sql)
module odood.lib.odoo.script;

private import std.algorithm: map;
private import std.string: join;
private import std.format: format;
private import std.exception: enforce;
private import std.typecons: Nullable, nullable;

private import thepath: Path;

private import odood.lib.project: Project;
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
