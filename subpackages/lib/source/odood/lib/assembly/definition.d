/** The assembly definition: what an assembly is, all sections of
  * `odood-assembly.yml` in one model, so that loading, saving and reloading
  * cannot forget one. A plain value: no path, git, network or Odoo serie;
  * `Assembly` adds those.
  **/
module odood.lib.assembly.definition;


private import dyaml: Node;

private import odood.lib.assembly.spec: AssemblySpec;
private import odood.lib.assembly.system_packages: AssemblySystemPackages;
private import odood.lib.assembly.packaging: AssemblyPackaging;
private import odood.lib.assembly.unknown_keys: findUnknownKeys, warnUnknownKeys;


/// Top-level keys of `odood-assembly.yml`.
private immutable string[] ASSEMBLY_TOP_LEVEL_KEYS = ["spec", "system-packages", "packaging"];


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

    /** Read a loaded `odood-assembly.yml`.
      *
      * A key odood does not know, at any level it reads, is not refused: a
      * file written by a newer odood still loads. It is logged as a warning;
      * saving the file drops it. A known key with a bad value is refused.
      *
      * Throws: `OdoodAssemblyInvalidSpecException` on an invalid section.
      **/
    this(in Node root) {
        spec = AssemblySpec(root);
        if (root.containsKey("system-packages"))
            system_packages = AssemblySystemPackages(root["system-packages"]);
        if (root.containsKey("packaging"))
            packaging = AssemblyPackaging(root["packaging"]);
        warnUnknownKeys(findUnknownKeys(root, ASSEMBLY_TOP_LEVEL_KEYS, ""));
    }

    /// The file to save. Sections left at their defaults are left out.
    Node toYAML() const {
        auto res = spec.toYAML;
        auto system_packages_node = system_packages.toYAML;
        if (!system_packages_node.isNull)
            res["system-packages"] = system_packages_node.get;
        auto packaging_node = packaging.toYAML;
        if (!packaging_node.isNull)
            res["packaging"] = packaging_node.get;
        return res;
    }
}

// Every section survives a save, at the top level of the file.
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

    auto saved = AssemblyDefinition(definition.toYAML);
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
        "  dockerfile:\n" ~
        "    generate: true\n" ~
        "pakaging: {}\n").load()
    ).packaging.dockerfile.with_odoo_requirements.shouldBeFalse;
}
