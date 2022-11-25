module odood.lib.zip;

private import std.stdio;
private import std.string: toStringz, fromStringz, strip;
private import std.format: format;
private import std.algorithm.searching: endsWith;
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


void extract_zip_archive(in Path archive, in Path destination) {
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

    // Create destination directory
    dest.mkdir(true);

    auto num_entries = zip_get_num_entries(zip_obj, 0);
    for(ulong i=0; i < num_entries; ++i) {
        zip_stat_t stat;
        zip_stat_index(zip_obj, i, 0, &stat);

        // TODO: check for memory leak
        string entry_name = cast(string)fromStringz(stat.name);

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
                out_file.rawWrite(buf);
                size_written += size_read;
            }
        }
    }

}
