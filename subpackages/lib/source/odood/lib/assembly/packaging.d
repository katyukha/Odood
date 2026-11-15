/** What odood produces from an assembly: the top-level `packaging` section of
  * `odood-assembly.yml`. For now it holds the options of the generated
  * Dockerfile (`packaging.dockerfile`).
  **/
module odood.lib.assembly.packaging;

private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable, nullable;

private import dyaml: Node, NodeType;

private import odood.lib.assembly.exception: OdoodAssemblyInvalidSpecException;
private import odood.lib.assembly.unknown_keys: findUnknownKeys, warnUnknownKeys;


/** Options of the generated Dockerfile (`packaging.dockerfile`). They apply
  * whenever the Dockerfile is generated; the section's presence does not make
  * odood generate it.
  **/
struct AssemblyDockerfileSettings {
    private bool _with_odoo_requirements;

    /** Read the `packaging.dockerfile` section. An unknown key is logged as a
      * warning.
      *
      * Throws: `OdoodAssemblyInvalidSpecException` unless it is a mapping and
      * every known option has a boolean value.
      **/
    this(in Node section) {
        enforce!OdoodAssemblyInvalidSpecException(
            section.nodeTypeString == "mapping",
            "Invalid assembly spec: 'packaging.dockerfile' must be a mapping, " ~
            "e.g. 'with-odoo-requirements: true'");
        warnUnknownKeys(findUnknownKeys(
            section, ["with-odoo-requirements"], "packaging.dockerfile."));
        if (section.containsKey("with-odoo-requirements")) {
            enforce!OdoodAssemblyInvalidSpecException(
                section["with-odoo-requirements"].type == NodeType.boolean,
                "Invalid assembly spec: " ~
                "'packaging.dockerfile.with-odoo-requirements' must be true or false");
            _with_odoo_requirements = section["with-odoo-requirements"].as!bool;
        }
    }

    /// The generated Dockerfile links the assembly with Odoo's requirements
    /// (`packaging.dockerfile.with-odoo-requirements`).
    @property bool with_odoo_requirements() const => _with_odoo_requirements;

    /// The section to save; null when every option has its default.
    Nullable!Node toYAML() const {
        if (!_with_odoo_requirements)
            return Nullable!Node.init;
        return Node(["with-odoo-requirements": true]).nullable;
    }
}


/// The top-level `packaging` section of `odood-assembly.yml`.
struct AssemblyPackaging {
    private AssemblyDockerfileSettings _dockerfile;

    /** Read the `packaging` section. An unknown key is logged as a
      * warning.
      *
      * Throws: `OdoodAssemblyInvalidSpecException` unless it is a mapping, and
      * on an invalid `dockerfile` section.
      **/
    this(in Node section) {
        enforce!OdoodAssemblyInvalidSpecException(
            section.nodeTypeString == "mapping",
            "Invalid assembly spec: 'packaging' must be a mapping, " ~
            "e.g. 'dockerfile: {with-odoo-requirements: true}'");
        warnUnknownKeys(findUnknownKeys(section, ["dockerfile"], "packaging."));
        if (section.containsKey("dockerfile"))
            _dockerfile = AssemblyDockerfileSettings(section["dockerfile"]);
    }

    /// Options of the generated Dockerfile (`packaging.dockerfile`).
    @property auto dockerfile() const => _dockerfile;

    /// Set `packaging.dockerfile.with-odoo-requirements`.
    package(odood) void setDockerfileWithOdooRequirements(in bool value) {
        _dockerfile._with_odoo_requirements = value;
    }

    /// The section to save; null when every setting has its default.
    Nullable!Node toYAML() const {
        auto dockerfile = _dockerfile.toYAML;
        if (dockerfile.isNull)
            return Nullable!Node.init;
        return Node(["dockerfile": dockerfile.get]).nullable;
    }
}

// packaging.dockerfile.with-odoo-requirements survives a save; it is off by
// default, and then the section is left out.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    auto packaging = AssemblyPackaging(Loader.fromString(
        "dockerfile:\n  with-odoo-requirements: true\n").load());
    packaging.dockerfile.with_odoo_requirements.shouldBeTrue;
    AssemblyPackaging(packaging.toYAML.get)
        .dockerfile.with_odoo_requirements.shouldBeTrue;

    AssemblyPackaging.init.dockerfile.with_odoo_requirements.shouldBeFalse;
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
}

// Unknown keys, in the section and in dockerfile, are not refused.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    AssemblyPackaging(Loader.fromString(
        "changelog: true\n" ~
        "dockerfile:\n" ~
        "  generate: true\n" ~
        "  with-odoo-requirement: true\n").load()
    ).dockerfile.with_odoo_requirements.shouldBeFalse;
}
