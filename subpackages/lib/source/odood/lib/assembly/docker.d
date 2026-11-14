/** Settings for building an assembly's Docker image: the top-level `docker`
  * section of `odood-assembly.yml`, beside `spec`, which describes what the
  * assembly contains.
  **/
module odood.lib.assembly.docker;

private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable, nullable;

private import dyaml: Node, NodeType;

private import odood.lib.assembly.exception: OdoodAssemblyInvalidSpecException;


/// The top-level `docker` section of `odood-assembly.yml`.
struct AssemblyDockerSettings {
    private bool _with_odoo_requirements;

    /** Read the `docker` section of a loaded `odood-assembly.yml`. Every
      * setting keeps its default when the section is absent.
      **/
    this(in Node file) {
        if (!file.containsKey("docker"))
            return;
        auto docker = file["docker"];
        enforce!OdoodAssemblyInvalidSpecException(
            docker.nodeTypeString == "mapping",
            "Invalid assembly spec: 'docker' must be a mapping, " ~
            "e.g. 'with-odoo-requirements: true'");
        // An unknown key fails, so a typo cannot drop a setting silently.
        foreach(key; docker.mappingKeys!string)
            enforce!OdoodAssemblyInvalidSpecException(
                key == "with-odoo-requirements",
                ("Invalid assembly spec: unsupported 'docker.%s', " ~
                 "only 'with-odoo-requirements' is supported").format(key));
        if (docker.containsKey("with-odoo-requirements")) {
            enforce!OdoodAssemblyInvalidSpecException(
                docker["with-odoo-requirements"].type == NodeType.boolean,
                "Invalid assembly spec: 'docker.with-odoo-requirements' " ~
                "must be true or false");
            _with_odoo_requirements = docker["with-odoo-requirements"].as!bool;
        }
    }

    /// The generated Dockerfile links the assembly with Odoo's requirements
    /// (`docker.with-odoo-requirements`).
    @property bool with_odoo_requirements() const => _with_odoo_requirements;

    /// Set `docker.with-odoo-requirements`.
    package(odood) void setWithOdooRequirements(in bool value) {
        _with_odoo_requirements = value;
    }

    /// The `docker` section to save; null when every setting has its default.
    Nullable!Node toYAML() const {
        if (!_with_odoo_requirements)
            return Nullable!Node.init;
        return Node(["with-odoo-requirements": true]).nullable;
    }
}

// docker.with-odoo-requirements survives a save; it is off by default, and
// then the section is left out.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    auto docker = AssemblyDockerSettings(Loader.fromString(
        "spec:\n" ~
        "  addons-list: []\n" ~
        "docker:\n" ~
        "  with-odoo-requirements: true\n").load());
    docker.with_odoo_requirements.shouldBeTrue;
    AssemblyDockerSettings(Node(["docker": docker.toYAML.get]))
        .with_odoo_requirements.shouldBeTrue;

    auto defaults = AssemblyDockerSettings(
        Loader.fromString("spec:\n  addons-list: []\n").load());
    defaults.with_odoo_requirements.shouldBeFalse;
    defaults.toYAML.isNull.shouldBeTrue;
}

// The docker section is refused unless it is a mapping of known keys to
// booleans.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    auto load(in string docker) => AssemblyDockerSettings(Loader.fromString(
        "spec:\n  addons-list: []\ndocker:" ~ docker).load());

    load(" [with-odoo-requirements]\n").shouldThrow!OdoodAssemblyInvalidSpecException;
    load("\n  with-odoo-requirement: true\n").shouldThrow!OdoodAssemblyInvalidSpecException;
    load("\n  with-odoo-requirements: 'yes please'\n")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
}
