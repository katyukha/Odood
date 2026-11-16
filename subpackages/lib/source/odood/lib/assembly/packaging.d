/** What odood produces from an assembly: the top-level `packaging` section of
  * the assembly definition, with the options of the generated Dockerfile
  * (`packaging.dockerfile`).
  **/
module odood.lib.assembly.packaging;

private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable, nullable;

private import dyaml: Node, NodeType;

private import odood.lib.assembly.exception: OdoodAssemblyInvalidSpecException;
private import odood.lib.assembly.unknown_keys: checkSection;


/// The generated Dockerfile (`packaging.dockerfile`).
struct AssemblyDockerfileSettings {
    private bool _generate;
    private bool _with_odoo_requirements;

    /** Read the `packaging.dockerfile` section. An unknown key is logged as a
      * warning.
      *
      * Throws: `OdoodAssemblyInvalidSpecException` unless it is a mapping and
      * every known option has a boolean value.
      **/
    this(in Node section) {
        checkSection(section, "packaging.dockerfile",
            ["generate", "with-odoo-requirements"], "generate: true");

        bool option(in string key) {
            if (!section.containsKey(key))
                return false;
            enforce!OdoodAssemblyInvalidSpecException(
                section[key].type == NodeType.boolean,
                ("Invalid assembly definition: 'packaging.dockerfile.%s' " ~
                 "must be true or false").format(key));
            return section[key].as!bool;
        }
        _generate = option("generate");
        _with_odoo_requirements = option("with-odoo-requirements");
    }

    /// `odood assembly sync` and `release` write the Dockerfile
    /// (`packaging.dockerfile.generate`).
    @property bool generate() const => _generate;

    /// The generated Dockerfile links the assembly with Odoo's requirements
    /// (`packaging.dockerfile.with-odoo-requirements`).
    @property bool with_odoo_requirements() const => _with_odoo_requirements;

    /// The section to save, with the options that are on; null when none is.
    Nullable!Node toYAML() const {
        auto res = Node(string[].init, bool[].init);
        if (_generate)
            res["generate"] = true;
        if (_with_odoo_requirements)
            res["with-odoo-requirements"] = true;
        if (res.length == 0)
            return Nullable!Node.init;
        return res.nullable;
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
        checkSection(section, "packaging", ["dockerfile"],
            "dockerfile: {generate: true}");
        if (section.containsKey("dockerfile"))
            _dockerfile = AssemblyDockerfileSettings(section["dockerfile"]);
    }

    /// Options of the generated Dockerfile (`packaging.dockerfile`).
    @property auto dockerfile() const => _dockerfile;

    /// Set `packaging.dockerfile.generate`.
    package(odood) void setDockerfileGenerate(in bool value) {
        _dockerfile._generate = value;
    }

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

// Each packaging.dockerfile option is read, and survives a save, on its own
// and together; both are off by default, and then the section is left out.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    void check(in string options, in bool generate, in bool with_odoo_requirements) {
        auto loaded = AssemblyPackaging(Loader.fromString("dockerfile: " ~ options).load());
        foreach(packaging; [loaded, AssemblyPackaging(loaded.toYAML.get)]) {
            packaging.dockerfile.generate.shouldEqual(generate);
            packaging.dockerfile.with_odoo_requirements.shouldEqual(with_odoo_requirements);
        }
    }
    check("{generate: true}", true, false);
    check("{with-odoo-requirements: true}", false, true);
    check("{generate: true, with-odoo-requirements: true}", true, true);

    AssemblyPackaging.init.dockerfile.generate.shouldBeFalse;
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
    load("dockerfile: {generate: 1}")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
}
