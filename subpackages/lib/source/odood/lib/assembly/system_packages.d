/** System packages any host running the assembly needs: the top-level
  * `system-packages` section of `odood-assembly.yml`. Servers install them,
  * and so does the generated Dockerfile.
  **/
module odood.lib.assembly.system_packages;

private import std.algorithm: canFind, filter;
private import std.array: array, empty;
private import std.exception: enforce;
private import std.format: format;
private import std.typecons: Nullable, nullable;

private import dyaml: Node;

private import odood.lib.assembly.exception: OdoodAssemblyInvalidSpecException;
private import odood.lib.assembly.unknown_keys: findUnknownKeys, warnUnknownKeys;
private import odood.lib.deb: isValidDebPackageName;


/// The top-level `system-packages` section of `odood-assembly.yml`.
struct AssemblySystemPackages {
    private string[] _deb;

    /** Read the `system-packages` section. An unknown key, such as a package
      * format odood does not support, is logged as a warning.
      *
      * Throws: `OdoodAssemblyInvalidSpecException` unless it is a mapping and
      * every package name is valid.
      **/
    this(in Node section) {
        enforce!OdoodAssemblyInvalidSpecException(
            section.nodeTypeString == "mapping",
            "Invalid assembly definition: 'system-packages' must map a package " ~
            "format to package names, e.g. 'deb: [ghostscript]'");
        warnUnknownKeys(findUnknownKeys(section, ["deb"], "system-packages."));
        if (section.containsKey("deb"))
            foreach(node; section["deb"].sequence) {
                auto name = node.as!string;
                enforceDebPackageName(name);
                _deb ~= name;
            }
    }

    /// Debian packages (`system-packages.deb`), in the order listed.
    @property auto deb() const => _deb;

    // The names reach apt-get, run as root.
    private static void enforceDebPackageName(in string name) {
        enforce!OdoodAssemblyInvalidSpecException(
            isValidDebPackageName(name),
            "'%s' in 'system-packages.deb' is not a valid Debian package name".format(
                name));
    }

    /// Add a Debian package. No-op if it is listed.
    package(odood) void addDeb(in string name) {
        enforceDebPackageName(name);
        if (!_deb.canFind(name))
            _deb ~= name;
    }

    /// Remove a Debian package. No-op if it is not listed.
    package(odood) void removeDeb(in string name) {
        _deb = _deb.filter!((p) => p != name).array;
    }

    /// The section to save; null when no package is listed.
    Nullable!Node toYAML() const {
        if (_deb.empty)
            return Nullable!Node.init;
        return Node(["deb": _deb]).nullable;
    }
}

// The list survives a save in its order; an empty list leaves the section out.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    auto packages = AssemblySystemPackages(
        Loader.fromString("deb:\n  - poppler-utils\n  - ghostscript\n").load());
    packages.deb.should == ["poppler-utils", "ghostscript"];
    AssemblySystemPackages(packages.toYAML.get).deb
        .should == ["poppler-utils", "ghostscript"];

    AssemblySystemPackages.init.toYAML.isNull.shouldBeTrue;
}

// The section is refused unless it is a mapping with valid package names.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    auto load(in string section) => AssemblySystemPackages(
        Loader.fromString(section).load());

    load("[ghostscript]").shouldThrow!OdoodAssemblyInvalidSpecException;
    load("deb: ['--allow-unauthenticated']")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
}

// An unknown key, such as an unsupported package format, is not refused.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    AssemblySystemPackages(Loader.fromString("debs: [ghostscript]\n").load())
        .deb.length.shouldEqual(0);
}

// addDeb / removeDeb keep the list free of duplicates and invalid names, and
// leave other entries in place.
unittest {
    import unit_threaded.assertions;

    AssemblySystemPackages packages;
    packages.addDeb("poppler-utils");
    packages.addDeb("ghostscript");
    packages.addDeb("poppler-utils");
    packages.deb.should == ["poppler-utils", "ghostscript"];

    packages.addDeb("--allow-unauthenticated")
        .shouldThrow!OdoodAssemblyInvalidSpecException;
    packages.deb.should == ["poppler-utils", "ghostscript"];

    packages.removeDeb("antiword");
    packages.removeDeb("poppler-utils");
    packages.deb.should == ["ghostscript"];
}
