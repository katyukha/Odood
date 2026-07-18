module odood.lib.assembly.source_env;

/** Credential/env resolution for assembly git sources, shared by the source
  * provider (clone/fetch) and the assembly's remote-tag-listing (upgrade check).
  * Kept separate from both so neither has to depend on the other.
  **/

private import std.exception: enforce;
private import std.format: format;
private import std.array: empty, split;
private import std.process: environment;

private import odood.lib.assembly.exception: OdoodAssemblyException;
private import odood.lib.assembly.spec: AssemblySpecSource;


/** Resolve git auth env for an assembly source.
  *
  * Looks up `ODOOD_ASSEMBLY_<name>_CRED` (or `_<access_group>_CRED`) as
  * `user:password` and turns it into git-config env for an https operation.
  * Returns an empty map when no matching credentials are configured.
  **/
package(odood) string[string] resolveSourceGitEnv(in AssemblySpecSource source) {
    string[string] result;

    // Try to find creds in environment
    string[] creds;
    if (!source.name.empty && "ODOOD_ASSEMBLY_%s_CRED".format(source.name) in environment)
        creds = environment["ODOOD_ASSEMBLY_%s_CRED".format(source.name)].split(":");
    else if (!source.access_group.empty && "ODOOD_ASSEMBLY_%s_CRED".format(source.access_group) in environment)
        creds = environment["ODOOD_ASSEMBLY_%s_CRED".format(source.access_group)].split(":");

    if (creds.length > 0) {
        enforce!OdoodAssemblyException(
            creds.length == 2,
            "Cannot parse creds from environment for %s".format(source.name.empty ? source.access_group : source.name));
        enforce!OdoodAssemblyException(
            "GIT_CONFIG_COUNT" !in environment,
            "Assembly source creds via environment not supported, when GIT_CONFIG_COUNT is present in environment.");
        enforce!OdoodAssemblyException(
            source.git_url.scheme == "https",
            "Assembly source creds via environment not supported for non-https sources.");
        string user = creds[0];
        string pass = creds[1];
        result["ODOOD__INT__ASSEMBLY_SOURCE_PASS"] = pass;
        result["GIT_CONFIG_COUNT"] = "2";
        result["GIT_CONFIG_KEY_0"] = "credential.username";
        result["GIT_CONFIG_VALUE_0"] = user;
        result["GIT_CONFIG_KEY_1"] = "credential.helper";
        result["GIT_CONFIG_VALUE_1"] = "!f() { test \"$1\" = get && echo \"password=${ODOOD__INT__ASSEMBLY_SOURCE_PASS}\"; }; f";
    }
    return result;
}
