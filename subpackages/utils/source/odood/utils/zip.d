module odood.utils.zip;

private import std.format: format;
private import std.exception: enforce;

private import thepath: Path;

private import odood.exception: OdoodException;

private import zipper: Zipper;

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

    auto zip = Zipper(archive.toAbsolute);
    zip.extractTo(destination, unfold_path);
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
