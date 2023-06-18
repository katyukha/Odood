module odood.utils.zip;

private import std.logger;
private import std.format: format;
private import std.algorithm.searching: endsWith, startsWith;
private import std.exception: enforce;

private import thepath: Path;

private import odood.exception: OdoodException;

public import odood.utils.zipper;

/** Extract zip archive to destination directory

    Also, if zip folder contains single directory, unpack its content
    directly to destination directory.
    Use **unfold_path** param for this case.

    Params:
        archive = path to zip archive to extract.
        destination = path to destination where to extract archive.
        unfold_path = if set, then unfold this path when unpacking.
**/
void extract_zip_archive(
        in Path archive,
        in Path destination,
        in string unfold_path=null) {
    enforce!OdoodException(
        archive.exists,
        "ZipArchive %s does not exists!".format(archive));
    enforce!OdoodException(
        !destination.exists,
        "Destination %s already exists!".format(destination));

    // TODO: Add protection for unzipping out of destinantion

    // TODO: Do we need this?
    auto source = archive.toAbsolute;
    auto dest = destination.toAbsolute;

    auto zip = Zipper(source);

    // Check if we can unfold path
    if (unfold_path) {
        enforce!OdoodException(
            unfold_path.endsWith("/"),
            "Unfold path must be ended with '/'");
        foreach(entry; zip.entries) {
            enforce!OdoodException(
                entry.name.startsWith(unfold_path),
                "Cannot unfold path %s, because there is entry %s that is not under this path".format(
                    unfold_path, entry.name));
        }
    }

    // Create destination directory
    dest.mkdir(true);

    foreach(entry; zip.entries) {
        string entry_name = entry.name.dup;

        if (unfold_path) {
            if (entry_name == unfold_path) {
                // Skip unfolded directory
                continue;
            }
            entry_name = entry_name[unfold_path.length .. $];
            enforce!OdoodException(
                entry_name,
                "Entry name is empty after unfolding!");
        }

        // Path to unzip entry to
        auto entry_dst = dest.join(entry_name);
        enforce!ZipException(
            entry_dst.isInside(dest),
            "Attempt to unzip entry %s out of scope of destination (%s)".format(
                entry.name, dest));

        // Unzip entry
        entry.unzipTo(entry_dst);
    }

}

/// Example of unarchiving archive
unittest {
    import unit_threaded.assertions;
    import thepath: createTempPath;

    Path temp_root = createTempPath("test-zip");
    scope(exit) temp_root.remove();

    extract_zip_archive(
        Path("test-data", "test-zip.zip"),
        temp_root.join("res"));

    temp_root.join("res", "test-zip").exists().shouldBeTrue();
    temp_root.join("res", "test-zip").isDir().shouldBeTrue();

    temp_root.join("res", "test-zip", "test.txt").exists().shouldBeTrue();
    temp_root.join("res", "test-zip", "test.txt").isFile().shouldBeTrue();
    temp_root.join("res", "test-zip", "test.txt").readFileText().shouldEqual("Test Root\n");

    temp_root.join("res", "test-zip", "test-dir", "test.txt").exists().shouldBeTrue();
    temp_root.join("res", "test-zip", "test-dir", "test.txt").isFile().shouldBeTrue();
    temp_root.join("res", "test-zip", "test-dir", "test.txt").readFileText().shouldEqual("Hello World!\n");

    temp_root.join("res", "test-zip", "test-link-1.txt").exists().shouldBeTrue();
    temp_root.join("res", "test-zip", "test-link-1.txt").isSymlink().shouldBeTrue();
    temp_root.join("res", "test-zip", "test-link-1.txt").readLink().shouldEqual(
        Path("test-dir", "test.txt"));
    temp_root.join("res", "test-zip", "test-link-1.txt").readFileText().shouldEqual("Hello World!\n");

    temp_root.join("res", "test-zip", "test-dir", "test-link.txt").exists().shouldBeTrue();
    temp_root.join("res", "test-zip", "test-dir", "test-link.txt").isSymlink().shouldBeTrue();
    temp_root.join("res", "test-zip", "test-dir", "test-link.txt").readLink().shouldEqual(
        Path("test.txt"));
    temp_root.join("res", "test-zip", "test-dir", "test-link.txt").readFileText().shouldEqual("Hello World!\n");

    temp_root.join("res", "test-zip", "test-dir", "test-parent.txt").exists().shouldBeTrue();
    temp_root.join("res", "test-zip", "test-dir", "test-parent.txt").isSymlink().shouldBeTrue();
    temp_root.join("res", "test-zip", "test-dir", "test-parent.txt").readLink().shouldEqual(
        Path("..", "test.txt"));
    temp_root.join("res", "test-zip", "test-dir", "test-parent.txt").readFileText().shouldEqual("Test Root\n");
}
