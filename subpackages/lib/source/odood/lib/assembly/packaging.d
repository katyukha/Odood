/** What odood produces from an assembly: the top-level `packaging` section of
  * the assembly definition. It names the files `odood assembly sync` and
  * `release` generate in the assembly repository, and the options of the
  * generated Dockerfile.
  **/
module odood.lib.assembly.packaging;

private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable, nullable;

private import dyaml: Node, NodeType;

private import odood.lib.assembly.exception: OdoodAssemblyInvalidSpecException;
private import odood.lib.assembly.unknown_keys: enforceMapping, findUnknownKeys;


/* The boolean option `key` of the section `path`; false when absent. */
private bool readOption(in Node section, in string path, in string key) {
    if (!section.containsKey(key))
        return false;
    enforce!OdoodAssemblyInvalidSpecException(
        section[key].type == NodeType.boolean,
        "Invalid assembly definition: '%s.%s' must be true or false".format(path, key));
    return section[key].as!bool;
}


/// The generated Dockerfile (`packaging.dockerfile`).
struct AssemblyDockerfileSettings {
    /// `odood assembly sync` and `release` write the Dockerfile (`generate`).
    /// Refused for a flat assembly.
    bool generate;

    /// The Dockerfile links the assembly with Odoo's requirements
    /// (`with-odoo-requirements`).
    bool with_odoo_requirements;

    /** Read the `packaging.dockerfile` section. An unknown key is not refused
      * (see `AssemblyPackaging.unknownKeys`).
      *
      * Throws: `OdoodAssemblyInvalidSpecException` unless it is a mapping and
      * every known option has a boolean value.
      **/
    this(in Node section) {
        enforceMapping(section, "packaging.dockerfile", "generate: true");
        generate = readOption(section, "packaging.dockerfile", "generate");
        with_odoo_requirements = readOption(
            section, "packaging.dockerfile", "with-odoo-requirements");
    }

    /// The section to save, with the options that are on; null when none is.
    Nullable!Node toYAML() const {
        auto res = Node(string[].init, bool[].init);
        if (generate)
            res["generate"] = true;
        if (with_odoo_requirements)
            res["with-odoo-requirements"] = true;
        if (res.length == 0)
            return Nullable!Node.init;
        return res.nullable;
    }
}


/** The top-level `packaging` section of `odood-assembly.yml`. A plain value:
  * `Assembly.setPackaging` checks it against the rest of the assembly
  * definition.
  **/
struct AssemblyPackaging {
    /// `odood assembly release` writes `CHANGELOG.md` and
    /// `CHANGELOG.latest.md` (`changelog`).
    bool changelog;

    /// `odood assembly release` creates `VERSION` when it is missing
    /// (`version-file`). An existing `VERSION` is updated either way.
    bool version_file;

    /// `odood assembly sync` and `release` write `ADDONS.md`
    /// (`addons-list-md`).
    bool addons_list_md;

    /// `odood assembly sync` and `release` write `ADDONS.csv`
    /// (`addons-list-csv`).
    bool addons_list_csv;

    /// The generated Dockerfile (`dockerfile`).
    AssemblyDockerfileSettings dockerfile;

    /** Read the `packaging` section. An unknown key is not refused (see
      * `unknownKeys`).
      *
      * Throws: `OdoodAssemblyInvalidSpecException` unless it is a mapping,
      * every option has a boolean value, and `dockerfile` is valid.
      **/
    this(in Node section) {
        enforceMapping(section, "packaging", "changelog: true");
        changelog = readOption(section, "packaging", "changelog");
        version_file = readOption(section, "packaging", "version-file");
        addons_list_md = readOption(section, "packaging", "addons-list-md");
        addons_list_csv = readOption(section, "packaging", "addons-list-csv");
        if (section.containsKey("dockerfile"))
            dockerfile = AssemblyDockerfileSettings(section["dockerfile"]);
    }

    /// The unknown keys of a valid `packaging` section, `dockerfile`
    /// included, fully qualified.
    package(odood) static string[] unknownKeys(in Node section) {
        auto res = findUnknownKeys(
            section,
            ["changelog", "version-file", "addons-list-md", "addons-list-csv",
             "dockerfile"],
            "packaging.");
        if (section.containsKey("dockerfile"))
            res ~= findUnknownKeys(
                section["dockerfile"], ["generate", "with-odoo-requirements"],
                "packaging.dockerfile.");
        return res;
    }

    /// The section to save, with the options that are on; null when none is.
    Nullable!Node toYAML() const {
        auto res = Node(string[].init, bool[].init);
        if (changelog)
            res["changelog"] = true;
        if (version_file)
            res["version-file"] = true;
        if (addons_list_md)
            res["addons-list-md"] = true;
        if (addons_list_csv)
            res["addons-list-csv"] = true;
        auto dockerfile_node = dockerfile.toYAML;
        if (!dockerfile_node.isNull)
            res["dockerfile"] = dockerfile_node.get;
        if (res.length == 0)
            return Nullable!Node.init;
        return res.nullable;
    }
}

// Each option is read, and survives a save, on its own: a mix-up between two
// options shows. All are off by default, and then the section is left out.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    // The options as [changelog, version-file, addons-list-md,
    // addons-list-csv, dockerfile.generate, dockerfile.with-odoo-requirements].
    bool[] options(in AssemblyPackaging p) => [
        p.changelog, p.version_file, p.addons_list_md, p.addons_list_csv,
        p.dockerfile.generate, p.dockerfile.with_odoo_requirements];

    void check(in string section, in bool[] expected) {
        auto loaded = AssemblyPackaging(Loader.fromString(section).load());
        options(loaded).shouldEqual(expected);
        options(AssemblyPackaging(loaded.toYAML.get)).shouldEqual(expected);
    }
    check("changelog: true", [true, false, false, false, false, false]);
    check("version-file: true", [false, true, false, false, false, false]);
    check("addons-list-md: true", [false, false, true, false, false, false]);
    check("addons-list-csv: true", [false, false, false, true, false, false]);
    check("dockerfile: {generate: true}", [false, false, false, false, true, false]);
    check("dockerfile: {with-odoo-requirements: true}",
        [false, false, false, false, false, true]);

    options(AssemblyPackaging.init).shouldEqual([false, false, false, false, false, false]);
    AssemblyPackaging.init.toYAML.isNull.shouldBeTrue;
}

// A known key with a bad value is refused: a section that is not a mapping,
// an option that is not a boolean.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    auto load(in string section) => AssemblyPackaging(
        Loader.fromString(section).load());

    load("[dockerfile]").shouldThrow!OdoodAssemblyInvalidSpecException;
    load("dockerfile: [with-odoo-requirements]")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
    load("dockerfile: {with-odoo-requirements: 'yes please'}")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
    load("dockerfile: {generate: 1}")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
    load("changelog: yes please").shouldThrow!OdoodAssemblyInvalidSpecException;
}
