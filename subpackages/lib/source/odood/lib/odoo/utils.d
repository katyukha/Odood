module odood.lib.odoo.utils;

private import std.logger;
private import std.string: toStringz, fromStringz, strip;
private import std.format: format;
private import std.exception: enforce;
private import std.json;

private import thepath: Path;

private import odood.exception: OdoodException;
private import odood.utils.odoo.serie: OdooSerie;


/// Resolve version conflict in provided manifest content.
string fixVersionConflictImpl(in string manifest_content, in OdooSerie serie) {
    import std.regex;
    import semver;

    auto immutable RE_CONFLICT = ctRegex!(
        `^<<<<<<< HEAD\n` ~
        `(?P<head>\s+["']version["']:\s["'](?P<headserie>\d+\.\d+)\.(?P<headver>\d+\.\d+\.\d+)["'],\n)` ~
        `=======\n` ~
        `(?P<changekey>\s+["']version["']:\s)(?P<changequote>["'])(?P<changeserie>\d+\.\d+)\.(?P<changever>\d+\.\d+\.\d+)["'],\n` ~
        `>>>>>>> .*\n`, "m");

    // function that is responsible for replace
    string fn_replace(Captures!(string) captures) {
        OdooSerie head_serie = captures["headserie"];
        SemVer head_version = captures["headver"];

        OdooSerie change_serie = captures["changeserie"];
        SemVer change_version = captures["changever"];

        auto new_ver = change_version > head_version ? change_version : head_version;

        // TODO: find better workaround
        assert(new_ver.isValid, "New version is not valid");

        return "%s%s%s.%s%s,\n".format(
            captures["changekey"],
            captures["changequote"],
            serie.toString,
            new_ver.toString,
            captures["changequote"],
        );
    }

    return manifest_content.replaceAll!(fn_replace)(RE_CONFLICT);
}

unittest {
    import unit_threaded.assertions;
    string manifest_content = `{
    'name': "Bureaucrat Helpdesk Pro [Obsolete]",
    'author': "Center of Research and Development",
    'website': "https://crnd.pro",
<<<<<<< HEAD
    'version': '15.0.1.10.0',
=======
    'version': '16.0.1.9.0',
>>>>>>> d1d911566 (Init port)
    'category': 'Helpdesk',
}`;

    manifest_content.fixVersionConflictImpl(OdooSerie(16)).shouldEqual(`{
    'name': "Bureaucrat Helpdesk Pro [Obsolete]",
    'author': "Center of Research and Development",
    'website': "https://crnd.pro",
    'version': '16.0.1.10.0',
    'category': 'Helpdesk',
}`);

}


/// Resove version conflict in manifest file by provided path
void fixVersionConflict(in Path manifest_path, in OdooSerie serie) {
    infof("Fixing version conflict in manifest: %s", manifest_path);
    string manifest_content = manifest_path.readFileText()
        .fixVersionConflictImpl(serie);
    manifest_path.writeFile(manifest_content);
}
