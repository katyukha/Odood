/** Keys of a mapping in the assembly definition (`odood-assembly.yml`) that
  * odood does not know.
  *
  * They are not refused, so a file written by a newer odood still loads on an
  * older one. They are logged as a warning, fully qualified, so a typo shows
  * up. Saving the file drops them.
  **/
module odood.lib.assembly.unknown_keys;

private import std.algorithm: canFind;
private import std.array: join;
private import std.logger: warningf;

private import dyaml: Node;


/// The keys of `mapping` that are not in `known`, each prefixed with `prefix`.
package(odood) string[] findUnknownKeys(
        in Node mapping, in string[] known, in string prefix) {
    string[] res;
    foreach(key; mapping.mappingKeys!string)
        if (!known.canFind(key))
            res ~= prefix ~ key;
    return res;
}

/// Log the unknown keys `names` (fully qualified) as a warning, if any.
package(odood) void warnUnknownKeys(in string[] names) {
    if (names.length > 0)
        warningf(
            "Assembly: Unknown keys in the assembly definition " ~
            "(odood-assembly.yml) are ignored, and dropped when it is saved: %s",
            names.join(", "));
}

// Unknown keys are listed in order, qualified with the prefix.
unittest {
    import dyaml: Loader;
    import unit_threaded.assertions;

    findUnknownKeys(
        Loader.fromString("deb: [a]\nrpm: [b]\napk: [c]\n").load(),
        ["deb"], "system-packages."
    ).should == ["system-packages.rpm", "system-packages.apk"];

    findUnknownKeys(Loader.fromString("deb: [a]\n").load(), ["deb"], "")
        .length.shouldEqual(0);
}
