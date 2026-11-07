module odood.lib.assembly.source_env;

/** Credential/env resolution for assembly git sources, shared by the source
  * provider (clone/fetch) and the assembly's remote-tag-listing (upgrade check).
  * Kept separate from both so neither has to depend on the other.
  **/

private import std.exception: enforce;
private import std.format: format;
private import std.array: empty, split;
private import std.process: environment;

private import odood.git: gitCredentialEnv;
private import odood.lib.assembly.exception: OdoodAssemblyException;
private import odood.lib.assembly.spec: AssemblySpecSource;
private import odood.lib.git_credentials: resolveGitCredentialEnv;


/** Resolve git auth env for an assembly source.
  *
  * Looks up `ODOOD_ASSEMBLY_<name>_CRED` (or `_<access_group>_CRED`) as
  * `user:password`, then `ODOOD_GIT_CREDENTIALS` (see
  * `odood.lib.git_credentials`), and turns the credentials into git-config
  * env for an https operation. Returns an empty map when no matching
  * credentials are configured.
  **/
package(odood) string[string] resolveSourceGitEnv(in AssemblySpecSource source) {
    // Try to find creds in environment
    string[] creds;
    if (!source.name.empty && "ODOOD_ASSEMBLY_%s_CRED".format(source.name) in environment)
        creds = environment["ODOOD_ASSEMBLY_%s_CRED".format(source.name)].split(":");
    else if (!source.access_group.empty && "ODOOD_ASSEMBLY_%s_CRED".format(source.access_group) in environment)
        creds = environment["ODOOD_ASSEMBLY_%s_CRED".format(source.access_group)].split(":");

    if (creds.length == 0)
        return resolveGitCredentialEnv(source.git_url);

    enforce!OdoodAssemblyException(
        creds.length == 2,
        "Cannot parse creds from environment for %s".format(source.name.empty ? source.access_group : source.name));
    enforce!OdoodAssemblyException(
        source.git_url.scheme == "https",
        "Assembly source creds via environment not supported for non-https sources.");
    return gitCredentialEnv(source.git_url, creds[0], creds[1]);
}

// ODOOD_ASSEMBLY_<name|group>_CRED take precedence over ODOOD_GIT_CREDENTIALS.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;
    import odood.git.credential: GIT_CREDENTIAL_PASSWORD_ENV;
    import odood.lib.assembly.spec: AssemblySpec;

    immutable string[string] preset = [
        "ODOOD_ASSEMBLY_grp_CRED": "user:group-token",
        "ODOOD_GIT_CREDENTIALS": "https://github.com/my-org user:org-token",
    ];
    auto saved = environment.toAA;
    foreach(key, value; preset)
        environment[key] = value;
    scope(exit) foreach(key; preset.keys) {
        if (auto old = key in saved)
            environment[key] = *old;
        else
            environment.remove(key);
    }

    auto sources = AssemblySpec(Loader.fromString(
        "spec:\n" ~ "  addons-list: []\n" ~ "  sources-list:\n" ~
        "    - url: https://github.com/my-org/grouped\n" ~
        "      access-group: grp\n" ~
        "    - url: https://github.com/my-org/repo\n" ~
        "    - url: git@github.com:my-org/repo\n").load()).sources;

    resolveSourceGitEnv(sources[0])[GIT_CREDENTIAL_PASSWORD_ENV].shouldEqual("group-token");
    resolveSourceGitEnv(sources[1])[GIT_CREDENTIAL_PASSWORD_ENV].shouldEqual("org-token");
    resolveSourceGitEnv(sources[2]).length.shouldEqual(0);
}
