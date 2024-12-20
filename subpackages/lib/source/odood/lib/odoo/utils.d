module odood.lib.odoo.utils;

private import std.logger;
private import std.regex;
private import std.string: toStringz, fromStringz, strip;
private import std.format: format;
private import std.exception: enforce;
private import std.json;

private import thepath: Path;

private import odood.exception: OdoodException;
private import odood.utils.odoo.serie: OdooSerie;
private import odood.utils.odoo.std_version: OdooStdVersion;


private auto immutable RE_VERSION_CONFLICT = ctRegex!(
    `^<<<<<<< HEAD\n` ~
    `(?P<head>\s+["']version["']:\s["'](?P<headversion>\d+\.\d+\.\d+\.\d+\.\d+)["'],\n)` ~
    `=======\n` ~
    `(?P<changekey>\s+["']version["']:\s)(?P<changequote>["'])(?P<changeversion>\d+\.\d+\.\d+\.\d+\.\d+)["'],\n` ~
    `>>>>>>> .*\n`, "m");

private auto immutable RE_MANIFEST_SERIE_VERSION = ctRegex!(
    `^(?P<verprefix>\s+["']version["']:\s["'])(?P<addonversion>\d+\.\d+\.\d+\.\d+\.\d+)(?P<versuffix>["'],\s*(#.*)?)$`, "m");


/// Resolve version conflict in provided manifest content.
string fixVersionConflictImpl(in string manifest_content, in OdooSerie serie) {
    // function that is responsible for replace
    string fn_replace(Captures!(string) captures) {
        const OdooStdVersion head_version = OdooStdVersion(captures["headversion"])
            .ensureIsStandard.withSerie(serie);
        const OdooStdVersion change_version = OdooStdVersion(captures["changeversion"])
            .ensureIsStandard.withSerie(serie);

        auto new_ver = change_version > head_version ? change_version : head_version;

        // TODO: find better way. Check if head and change versions are valid
        assert(new_ver.isStandard, "New version is not valid!");

        return "%s%s%s%s,\n".format(
            captures["changekey"],
            captures["changequote"],
            new_ver.toString,
            captures["changequote"],
        );
    }

    return manifest_content.replaceAll!(fn_replace)(RE_VERSION_CONFLICT);
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

/// Update Odoo serie in manifest to specified.
string updateManifestSerieImpl(in string manifest_content, in OdooSerie serie) {
    return manifest_content.replaceAll!((Captures!(string) captures) {
        const OdooStdVersion new_version  = OdooStdVersion(captures["addonversion"])
            .ensureIsStandard.withSerie(serie);

        // TODO: find better way. Check if head and change versions are valid
        assert(new_version.isStandard, "New version is not valid!");

        return "%s%s%s".format(
            captures["verprefix"],
            new_version.toString,
            captures["versuffix"],
        );
    })(RE_MANIFEST_SERIE_VERSION);
}

unittest {
    import unit_threaded.assertions;
    string manifest_content = `{
    'name': "Bureaucrat Helpdesk Pro [Obsolete]",
    'author': "Center of Research and Development",
    'website': "https://crnd.pro",
    'version': '16.0.1.10.0',
    'category': 'Helpdesk',
}`;

    manifest_content.updateManifestSerieImpl(OdooSerie(17)).shouldEqual(`{
    'name': "Bureaucrat Helpdesk Pro [Obsolete]",
    'author': "Center of Research and Development",
    'website': "https://crnd.pro",
    'version': '17.0.1.10.0',
    'category': 'Helpdesk',
}`);
}

/// Update serie in manifest
void updateManifestSerie(in Path manifest_path, in OdooSerie serie) {
    infof("Updating serie in manifest: %s", manifest_path);
    string manifest_content = manifest_path.readFileText()
        .updateManifestSerieImpl(serie);
    manifest_path.writeFile(manifest_content);
}
