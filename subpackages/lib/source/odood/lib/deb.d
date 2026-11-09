/** Debian packages on this host: which are installed, and installing more.
  **/
module odood.lib.deb;

private import std.array: empty, split;
private import std.ascii: isDigit, isLower;
private import std.string: splitLines;
private import std.typecons: Nullable, nullable;

private import theprocess: Process, resolveProgram;


/** Check a name against Debian policy for package names: lowercase letters,
  * digits, `+`, `-` and `.`, at least two characters, starting with a letter
  * or digit.
  *
  * Callers pass such names to `apt-get` as arguments; a valid name can never
  * be read as an option.
  **/
bool isValidDebPackageName(in string name) pure nothrow @safe @nogc {
    if (name.length < 2 || !(name[0].isLower || name[0].isDigit))
        return false;
    foreach(c; name)
        if (!(c.isLower || c.isDigit || c == '+' || c == '-' || c == '.'))
            return false;
    return true;
}

///
unittest {
    assert(isValidDebPackageName("libreoffice-writer"));
    assert(isValidDebPackageName("g++"));
    assert(isValidDebPackageName("libgtk2.0-0"));
    assert(isValidDebPackageName("7zip"));

    assert(!isValidDebPackageName("x"));
    assert(!isValidDebPackageName("--allow-unauthenticated"));
    assert(!isValidDebPackageName("Ghostscript"));
    assert(!isValidDebPackageName("ghostscript poppler-utils"));
    assert(!isValidDebPackageName("ghostscript;id"));
    assert(!isValidDebPackageName("ghostscript=10.0"));
    assert(!isValidDebPackageName("libc6:i386"));
}


/** Find which of `packages` are not installed on this host.
  *
  * Returns: the missing names, in the given order; null when the host has no
  *     dpkg, i.e. is not Debian-based. Nothing is missing from an empty list,
  *     on any host.
  **/
Nullable!(string[]) debMissingPackages(in string[] packages) {
    if (packages.empty)
        return nullable(string[].init);
    if (resolveProgram("dpkg-query").isNull)
        return Nullable!(string[]).init;

    /* Every package dpkg knows, not just the ones asked for: an unknown name
     * makes dpkg-query fail and report it on stderr, which `execute` mixes
     * into the output it returns. */
    bool[string] installed;
    auto listing = Process("dpkg-query")
        .withArgs("--show", "--showformat=${Package}\t${db:Status-Status}\n")
        .execute
        .ensureOk(true)
        .output;
    foreach(line; listing.splitLines) {
        auto fields = line.split("\t");
        // A removed package that kept its config files is "config-files".
        if (fields.length == 2 && fields[1] == "installed")
            installed[fields[0]] = true;
    }

    string[] missing;
    foreach(name; packages)
        if (name !in installed)
            missing ~= name;
    return missing.nullable;
}

unittest {
    import unit_threaded.assertions;

    debMissingPackages([]).get.should == string[].init;

    if (resolveProgram("dpkg-query").isNull)
        return;

    // dpkg-query comes from the dpkg package, so it is installed wherever this runs.
    debMissingPackages(["odood-no-such-b", "dpkg", "odood-no-such-a"]).get
        .should == ["odood-no-such-b", "odood-no-such-a"];
}


/** Install `packages` with `apt-get`, refreshing the package lists first.
  * Needs root.
  *
  * Params:
  *     packages = names that pass `isValidDebPackageName`
  **/
void debInstallPackages(in string[] packages) {
    // Package scripts must not stop to ask questions on a terminal.
    auto apt = Process("apt-get").withEnv("DEBIAN_FRONTEND", "noninteractive");
    apt.withArgs("update", "-qq")
        .execute
        .ensureOk("Cannot update the apt package lists", true);
    apt.withArgs("install", "-y", "-qq", "--no-install-recommends", "--")
        .withArgs(packages)
        .execute
        .ensureOk("Cannot install Debian packages", true);
}
