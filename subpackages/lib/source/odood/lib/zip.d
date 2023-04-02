module odood.lib.zip;

private import std.logger;
private import std.stdio;
private import std.string: toStringz, fromStringz, strip;
private import std.format: format;
private import std.algorithm.searching: endsWith, startsWith;
private import std.path;
private import std.exception: enforce;
private import std.typecons: Nullable, nullable;
private import std.json;

private import deimos.zip;

private import thepath: Path;

private import odood.lib.exception: OdoodException;

immutable BUF_SIZE = 1024;


/** Convert ZIP error specified by error_code to string
  *
  * Params:
  *     error_code = Code of error
  * Returns:
  *     string that contains error message
  **/
string format_zip_error(int error_code) {
    zip_error_t error;
    zip_error_init_with_code(&error, error_code);
    scope(exit) zip_error_fini(&error);
    return cast(string)zip_error_strerror(&error).fromStringz;
}


/** Simple struct to handle zip entries
  **/
struct ZipEntry {
    private const ulong index;
    private zip_t* _archive;

    private zip_stat_t _stat;
    private bool zip_stat_init = false;
    private Nullable!string _name;
    private Nullable!uint _attributes;

    @disable this();

    this(zip_t* archive, in ulong index) {
        this._archive = archive;
        this.index = index;
    }

    /** Get stat-info about this entry
      **/
    @property zip_stat_t stat() {
        if (!zip_stat_init) {
            auto stat_result = zip_stat_index(_archive, index, ZIP_FL_ENC_GUESS, &_stat);
            enforce!OdoodException(
                stat_result == 0,
                "Cannot get stat for entry %s in zip archive: %s".format(
                    index, zip_error_strerror(zip_get_error(_archive)).fromStringz));
        }
        return _stat;
    }

    /** Get name of this zip entry
      **/
    @property string name() {
        if (_name.isNull) {

            // Save name and strip leading "/" if entry name accidentally starts with "/"
            // TODO: do we need cast here?
            _name = (cast(string)fromStringz(stat.name)).strip("/", "").nullable;
        }
        return _name.get;
    }

    /** Get external attributes of this entry
      **/
    @property uint attributes() {
        if (_attributes.isNull) {
            ubyte entry_opsys;
            uint entry_attributes;

            auto attr_result = zip_file_get_external_attributes(
                    _archive, index, ZIP_FL_UNCHANGED, &entry_opsys, &entry_attributes);
            enforce!OdoodException(
                attr_result == 0,
                "Cannot get external file attrubutes for entry %s [%s] in zip archive: %s".format(
                    name, index, zip_error_strerror(zip_get_error(_archive)).fromStringz));

            if (entry_opsys == ZIP_OPSYS_UNIX) {
                entry_attributes = entry_attributes >> 16;
            } else {
                entry_attributes = 0;
            }
            _attributes = entry_attributes.nullable;
        }
        return _attributes.get;
    }

    /** Compute string representation of this entry
      **/
    string toString() {
        return "ZipEntry: " ~ name;
    }

    /** Check if this entry is symlink
      **/
    bool is_symlink() {
        if (attributes) {
            import core.sys.posix.sys.stat;
            return (attributes & S_IFMT) == S_IFLNK;
        }
        return false;
    }

    /** Check if this entry is directory
      **/
    bool is_directory() {
        if (attributes) {
            import core.sys.posix.sys.stat;
            return (attributes & S_IFMT) == S_IFDIR;
        }
        return name.endsWith("/");
    }

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
        source.toStringz, ZIP_RDONLY, &error_code);
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
                "Cannot unfold path %s, because there is entry %s that is not under this path".format(
                    unfold_path, entry_name));
        }
    }

    // Create destination directory
    dest.mkdir(true);

    for(ulong i=0; i < num_entries; ++i) {
        auto entry = ZipEntry(zip_obj, i);

        auto entry_name = entry.name;

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

        // TODO: May be it have sense to move part of this processing to ZipEntry struct
        if (entry.is_symlink) {
            auto afile = zip_fopen_index(zip_obj, i, ZIP_FL_ENC_GUESS);
            scope(exit) zip_fclose(afile);

            byte[] link_data;
            ulong size_written = 0;
            while (size_written != entry.stat.size) {
                byte[BUF_SIZE] chunk;
                auto size_read = zip_fread(afile, &chunk, BUF_SIZE);
                enforce!OdoodException(
                    size_read > 0,
                    "Cannot read file %s. Read: %s/%s".format(
                        entry_name, size_written, entry.stat.size));
                link_data ~= chunk[0 .. size_read];
                size_written += size_read;
            }
            auto link_target = Path(cast(string) link_data);
            enforce!OdoodException(
                link_target.isValid(),
                "Cannot handle zip entry %s: the data '%s'(%s) is not valid path".format(
                    entry.name, link_target, link_data));

            // We have to ensure that parent directory created
            entry_dst.parent.mkdir(true);

            link_target.symlink(entry_dst);
        } else if (entry.is_directory) {
            // It it is directory, then we have to create one in destination.
            entry_dst.mkdir(true);
        } else {
            // If it is file, then we have to extract file.

            // ensure the directory for this file created.
            entry_dst.parent.mkdir(true);

            auto out_file = std.stdio.File(entry_dst.toString, "wb");
            scope(exit) out_file.close();

            auto afile = zip_fopen_index(zip_obj, i, ZIP_FL_ENC_GUESS);
            scope(exit) zip_fclose(afile);

            ulong size_written = 0;
            while (size_written != entry.stat.size) {
                byte[BUF_SIZE] buf;
                auto size_read = zip_fread(afile, &buf, BUF_SIZE);
                enforce!OdoodException(
                    size_read > 0,
                    "Cannot read file %s. Read: %s/%s".format(
                        entry_name, size_written, entry.stat.size));
                out_file.rawWrite(buf[0 .. size_read]);
                size_written += size_read;
            }
        }
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
