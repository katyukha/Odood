/** The assembly definition: what an assembly is, all sections of
  * `odood-assembly.yml` in one model, so that loading, saving and reloading
  * cannot forget one. A plain value: no path, git, network or Odoo serie;
  * `Assembly` adds those.
  **/
module odood.lib.assembly.definition;


private import std.exception: enforce;
private import std.format: format;

private import dyaml: Node, NodeType;

private import odood.lib: _version;
private import odood.lib.assembly.exception: OdoodAssemblyInvalidSpecException;

private import odood.lib.assembly.spec: AssemblySpec, AssemblyLayout;
private import odood.lib.assembly.system_packages: AssemblySystemPackages;
private import odood.lib.assembly.packaging: AssemblyPackaging;
private import odood.lib.assembly.unknown_keys: enforceMapping, findUnknownKeys;


/// Top-level keys of `odood-assembly.yml`.
private immutable string[] ASSEMBLY_TOP_LEVEL_KEYS = [
    "meta", "spec", "system-packages", "packaging"];

/** The newest format of `odood-assembly.yml` this odood reads
  * (`meta.format-version`). It changes only when a key moves, is renamed or
  * changes meaning; an added key does not change it.
  **/
private enum ASSEMBLY_FORMAT_VERSION = 1;


/* `meta` says how to read the rest of the file, so it is checked before any
 * other section, and a later format may only add keys to it. Without
 * `format-version` the file is format 1. */
private void checkMeta(in Node root) {
    if (!root.containsKey("meta"))
        return;
    auto meta = root["meta"];
    if (meta.nodeTypeString == "mapping" && meta.containsKey("format-version")) {
        auto value = meta["format-version"];
        enforce!OdoodAssemblyInvalidSpecException(
            value.type == NodeType.integer && value.as!long >= 1,
            "Invalid assembly definition: 'meta.format-version' must be a " ~
            "positive integer");
        enforce!OdoodAssemblyInvalidSpecException(
            value.as!long <= ASSEMBLY_FORMAT_VERSION,
            ("The assembly definition (odood-assembly.yml) has format " ~
             "version %s, and odood %s reads up to format version %s: " ~
             "upgrade odood.").format(value.as!long, _version, ASSEMBLY_FORMAT_VERSION));
    }
    enforceMapping(meta, "meta", "format-version: 1");
}


/* A flat assembly keeps its addons in the repository root, which the
 * Dockerfile template does not copy: the image would have no addons. */
package(odood) void enforceDockerfileLayout(in AssemblyLayout layout, in bool generate) {
    enforce!OdoodAssemblyInvalidSpecException(
        !generate || layout != AssemblyLayout.FLAT,
        "Invalid assembly definition: 'packaging.dockerfile.generate' needs " ~
        "'layout: standard'; a flat assembly cannot build a Docker image");
}


/** The assembly definition, the sections of `odood-assembly.yml`:
  *
  * - `spec`: what the assembly contains;
  * - `system-packages`: what any host running it needs;
  * - `packaging`: what odood produces from it.
  **/
struct AssemblyDefinition {
    /// What the assembly contains (`spec`).
    AssemblySpec spec;

    /// System packages any host running the assembly needs (`system-packages`).
    AssemblySystemPackages system_packages;

    /// What odood produces from the assembly (`packaging`).
    AssemblyPackaging packaging;

    /** Read a loaded `odood-assembly.yml`. Nothing is logged.
      *
      * A key odood does not know, at any level it reads, is not refused: a
      * file written by a newer odood still loads (`unknownKeys` lists them).
      * A known key with a bad value is refused, and so is a format newer than
      * this odood reads (`meta.format-version`).
      *
      * Throws: `OdoodAssemblyInvalidSpecException` on an invalid section or
      * an unsupported format.
      **/
    this(in Node root) {
        checkMeta(root);
        spec = AssemblySpec(root);
        if (root.containsKey("system-packages"))
            system_packages = AssemblySystemPackages(root["system-packages"]);
        if (root.containsKey("packaging"))
            packaging = AssemblyPackaging(root["packaging"]);
        enforceDockerfileLayout(spec.layout, packaging.dockerfile.generate);
    }

    /** The keys of a loaded `odood-assembly.yml` that odood does not know,
      * at every level, fully qualified (`spec.addons-list[web].freeze`).
      * For a file that reads without error.
      **/
    static string[] unknownKeys(in Node root) {
        auto res = findUnknownKeys(root, ASSEMBLY_TOP_LEVEL_KEYS, "");
        if (root.containsKey("meta"))
            res ~= findUnknownKeys(root["meta"], ["format-version"], "meta.");
        res ~= AssemblySpec.unknownKeys(root["spec"]);
        if (root.containsKey("system-packages"))
            res ~= AssemblySystemPackages.unknownKeys(root["system-packages"]);
        if (root.containsKey("packaging"))
            res ~= AssemblyPackaging.unknownKeys(root["packaging"]);
        return res;
    }

    /** The file to save, `meta` first. Sections left at their defaults are
      * left out.
      *
      * `meta.format-version` is written on every save, though a file without
      * it is format 1: a file edited by a newer odood then says which format
      * it needs.
      **/
    Node toYAML() const {
        auto res = Node(["meta": Node(["format-version": ASSEMBLY_FORMAT_VERSION])]);
        res["spec"] = spec.toYAML["spec"];
        auto system_packages_node = system_packages.toYAML;
        if (!system_packages_node.isNull)
            res["system-packages"] = system_packages_node.get;
        auto packaging_node = packaging.toYAML;
        if (!packaging_node.isNull)
            res["packaging"] = packaging_node.get;
        return res;
    }
}

// Every section survives a save, at the top level of the file, and the save
// states the format.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    auto definition = AssemblyDefinition(Loader.fromString(
        "spec:\n" ~
        "  addons-list:\n" ~
        "    - name: generic_mixin\n" ~
        "system-packages:\n" ~
        "  deb: [poppler-utils]\n" ~
        "packaging:\n" ~
        "  dockerfile:\n" ~
        "    with-odoo-requirements: true\n").load());

    auto yaml = definition.toYAML;
    yaml["meta"]["format-version"].as!int.shouldEqual(ASSEMBLY_FORMAT_VERSION);
    auto saved = AssemblyDefinition(yaml);
    saved.spec.addons.length.shouldEqual(1);
    saved.system_packages.deb.should == ["poppler-utils"];
    saved.packaging.dockerfile.with_odoo_requirements.shouldBeTrue;
}

// A file with unknown keys at every level loads: a file written by a newer
// odood is not refused.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    AssemblyDefinition(Loader.fromString(
        "spec:\n" ~
        "  addons-list: []\n" ~
        "  known-addon: [sale]\n" ~
        "system-packages:\n" ~
        "  rpm: [poppler-utils]\n" ~
        "packaging:\n" ~
        "  helm-chart: true\n" ~
        "  dockerfile:\n" ~
        "    base-image: odoo:18\n" ~
        "pakaging: {}\n").load()
    ).packaging.dockerfile.with_odoo_requirements.shouldBeFalse;
}

// A generated Dockerfile is refused for a flat assembly, which it could not
// build an image of.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    auto load(in string layout) => AssemblyDefinition(Loader.fromString(
        "spec:\n  addons-list: []\n  layout: " ~ layout ~ "\n" ~
        "packaging:\n  dockerfile:\n    generate: true\n").load());

    load("standard").packaging.dockerfile.generate.shouldBeTrue;
    load("flat").shouldThrow!OdoodAssemblyInvalidSpecException;
}

// meta.format-version: absent or 1 loads, a newer format is refused before any
// other section is read, and a value that is not a positive integer is
// refused.
unittest {
    import std.algorithm: canFind;
    import std.exception: collectException;
    import dyaml: Loader;
    import unit_threaded.assertions;

    auto load(in string text) => AssemblyDefinition(Loader.fromString(text).load());

    load("spec:\n  addons-list: []\n");
    load("meta:\n  format-version: 1\nspec:\n  addons-list: []\n");

    // The spec of a newer format may not parse at all: the format error comes first.
    auto e = collectException!OdoodAssemblyInvalidSpecException(
        load("meta:\n  format-version: 2\nspec: [moved]\n"));
    (e !is null).shouldBeTrue;
    e.msg.canFind("format version 2").shouldBeTrue;

    load("meta:\n  format-version: 0\nspec:\n  addons-list: []\n")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
    load("meta:\n  format-version: '1'\nspec:\n  addons-list: []\n")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
    load("meta: [format-version]\nspec:\n  addons-list: []\n")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
}

// unknownKeys lists the unknown keys of every level, meta included; a
// file with only known keys has none.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    AssemblyDefinition.unknownKeys(Loader.fromString(
        "meta:\n" ~
        "  written-by: odood\n" ~
        "spec:\n" ~
        "  addons-list:\n" ~
        "    - name: generic_mixin\n" ~
        "      freeze: true\n" ~
        "system-packages:\n" ~
        "  rpm: [poppler-utils]\n" ~
        "packaging:\n" ~
        "  dockerfile:\n" ~
        "    base-image: odoo:18\n" ~
        "pakaging: {}\n").load()
    ).should == [
        "pakaging", "meta.written-by", "spec.addons-list[generic_mixin].freeze",
        "system-packages.rpm", "packaging.dockerfile.base-image"];

    AssemblyDefinition.unknownKeys(Loader.fromString(
        "meta:\n  format-version: 1\nspec:\n  addons-list: []\n").load()
    ).length.shouldEqual(0);
}
