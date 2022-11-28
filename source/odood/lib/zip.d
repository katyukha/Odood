module odood.lib.zip;

private import std.stdio;
private import std.string: toStringz, fromStringz, strip;
private import std.format: format;
private import std.algorithm.searching: endsWith, startsWith;
private import std.path;
private import std.file;
private import std.exception: enforce;

private import deimos.zip;

private import thepath: Path;

private import odood.lib.exception: OdoodException;

immutable BUF_SIZE = 1024;


string format_zip_error(int error_code) {
    zip_error_t error;
    zip_error_init_with_code(&error, error_code);
    scope(exit) zip_error_fini(&error);
    return cast(string)zip_error_strerror(&error).fromStringz;
}


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

    // TODO: Do we need this?
    auto source = archive.toAbsolute;
    auto dest = destination.toAbsolute;

    int error_code;
    auto zip_obj = zip_open(
        source.toString.toStringz, ZIP_RDONLY, &error_code);
    scope(exit) zip_close(zip_obj);
    enforce!OdoodException(
        !error_code,
        "Cannot open zip archive %s for reading: %s".format(
            source, format_zip_error(error_code)));

    auto num_entries = zip_get_num_entries(zip_obj, ZIP_FL_ENC_GUESS);

    // Check if we can unfold path
    if (unfold_path) {
        enforce!OdoodException(
            unfold_path.endsWith("/"),
            "Unfold path must be ended with '/'");
        for(ulong i=0; i < num_entries; ++i) {
            auto entry_name = zip_get_name(
                    zip_obj, i, ZIP_FL_ENC_GUESS).fromStringz;
            enforce!OdoodException(
                entry_name,
                "Cannot get name for zip entry %s: %s".format(
                    i, zip_error_strerror(zip_get_error(zip_obj)).fromStringz));
            enforce!OdoodException(
                entry_name.startsWith(unfold_path),
                "Cannot unfold path %s, because there is entry %s that is not " ~
                "under this path".format(
                    unfold_path, entry_name));
        }
    }

    // Create destination directory
    dest.mkdir(true);

    for(ulong i=0; i < num_entries; ++i) {
        zip_stat_t stat;
        auto stat_result = zip_stat_index(zip_obj, i, ZIP_FL_ENC_GUESS, &stat);
        enforce!OdoodException(
            stat_result == 0,
            "Cannot get stat for entry %s in zip archive: %s".format(
                i, zip_error_strerror(zip_get_error(zip_obj)).fromStringz));

        // TODO: check for memory leak
        string entry_name = cast(string)fromStringz(stat.name);

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

        // If, by ocasion, name is started with '/', then remove leading '/',
        // before futher processing.
        entry_name = entry_name.strip("/", "");

        auto entry_dst = dest.join(entry_name);

        if (entry_name.endsWith("/")) {
            // It it is directory, then we have to create one in destination.
            entry_dst.mkdir(true);
        } else {
            // If it is file, then we have to extract file.

            auto out_file = std.stdio.File(entry_dst.toString, "wb");
            scope(exit) out_file.close();

            auto afile = zip_fopen_index(zip_obj, i, ZIP_FL_ENC_GUESS);
            scope(exit) zip_fclose(afile);

            ulong size_written = 0;
            while (size_written != stat.size) {
                byte[BUF_SIZE] buf;
                auto size_read = zip_fread(afile, &buf, BUF_SIZE);
                enforce!OdoodException(
                    size_read > 0,
                    "Cannot read file %s. Read: %s/%s".format(
                        entry_name, size_written, stat.size));
                out_file.rawWrite(buf[0 .. size_read]);
                size_written += size_read;
            }
        }
    }

}
