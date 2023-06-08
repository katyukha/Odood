module odood.lib.zip;

private import std.logger;
private import std.string: toStringz, fromStringz, strip;
private import std.format: format;
private import std.algorithm.searching: endsWith, startsWith;
private import std.path;
private import std.exception: enforce, basicExceptionCtors;
private import std.typecons;
private import std.json;
private import std.datetime.systime;

private import deimos.zip;

private import thepath: Path;

private import odood.lib.exception: OdoodException;

immutable BUF_SIZE = 1024;


class ZipException : Exception
{
    mixin basicExceptionCtors;
}


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


struct Zipper {

    private:
        struct ZipPtr {
            private zip_t* zip_ptr;

            this(zip_t* zip_ptr) {
                this.zip_ptr = zip_ptr;
            }

            ~this() {
                if (zip_ptr !is null) {
                    zip_close(zip_ptr);
                    zip_ptr = null;
                }
            }

            // Must not be copiable
            @disable this(this);

            // Must not be assignable
            @disable void opAssign(typeof(this));
        }

        alias RefCounted!(ZipPtr, RefCountedAutoInitialize.no) ZipFile;

        ZipFile _zipfile;
    public:

        enum ZipMode {
            CREATE = ZIP_CREATE,
            EXCLUSIVE = ZIP_EXCL,
            TRUNCATE = ZIP_TRUNCATE,
            READONLY = ZIP_RDONLY,
            CHECK_CONSISTENCY = ZIP_CHECKCONS,
        };

        /** Struct to represent stat info about zip entry
          **/
        struct ZipEntryStat {
            private:
                string _name;
                ulong _index;
                ulong _size;
                ulong _compressed_size;
                SysTime _mtime;

                @disable this();

                this(scope const ref zip_stat_t stat) {
                    _name = (cast(string)fromStringz(stat.name)).strip("/", "");
                    _index = stat.index;
                    _size = stat.size;
                    _compressed_size = stat.comp_size;
                    _mtime = SysTime(stat.mtime.unixTimeToStdTime);
                }

            public:
                /// Name of zip entry
                auto name() const { return _name; }

                /// Index of zip entry
                auto index() const { return _index; }

                /// size of zip entry
                auto size() const { return _size; }

                /// compressed size of zip entry
                auto compressed_size() const { return _compressed_size; }
                auto mtime() const { return _mtime; }
        }

        /** Simple struct to handle zip entries
          **/
        struct ZipEntry {
            private ZipFile _zip_file;
            private ulong _index;
            private string _name;
            private Nullable!ZipEntryStat _stat;
            private Nullable!uint _attributes;

            @disable this();

            this(ZipFile zip_file, in ulong index) {
                _zip_file = zip_file;
                _index = index;
                // Save name and strip leading "/" if entry name accidentally starts with "/"
                // TODO: do we need cast here?
                _name = zip_get_name(
                    _zip_file.zip_ptr, index, ZIP_FL_ENC_GUESS
                ).fromStringz.idup.strip("/", "");
            }

            /// Name of the entry
            auto name() const { return _name; }

            /// Compute string representation of this entry
            string toString() { return "ZipEntry: " ~ _name; }

            /** Get stat-info about this entry
              **/
            auto stat() {
                if (_stat.isNull) {
                    zip_stat_t e_stat;
                    auto stat_result = zip_stat_index(
                        _zip_file.zip_ptr, _index, ZIP_FL_ENC_GUESS, &e_stat);
                    enforce!ZipException(
                        stat_result == 0,
                        "Cannot get stat for entry %s [%s] in zip archive: %s".format(
                            _name,
                            _index,
                            zip_error_strerror(
                                zip_get_error(_zip_file.zip_ptr)).fromStringz));
                    _stat = ZipEntryStat(e_stat).nullable;
                }
                return _stat.get;
            }

            /** Get external attributes of this entry
              **/
            uint attributes() {
                if (_attributes.isNull) {
                    ubyte entry_opsys;
                    uint entry_attributes;

                    auto attr_result = zip_file_get_external_attributes(
                        _zip_file.zip_ptr, _index, ZIP_FL_UNCHANGED,
                        &entry_opsys, &entry_attributes);
                    enforce!ZipException(
                        attr_result == 0,
                        "Cannot get external file attrubutes for entry %s [%s] in zip archive: %s".format(
                            _name, _index,
                            zip_error_strerror(zip_get_error(_zip_file.zip_ptr)).fromStringz));

                    if (entry_opsys == ZIP_OPSYS_UNIX) {
                        entry_attributes = entry_attributes >> 16;
                    } else {
                        entry_attributes = 0;
                    }
                    _attributes = entry_attributes.nullable;
                }
                return _attributes.get;
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

            /** Unzip entry to specified path
              *
              * Params:
              *     dest = destination path to unzip entry
              **/
            void unzipTo(in Path dest) {
                if (is_symlink) {
                    auto afile = zip_fopen_index(
                        _zip_file.zip_ptr, _index, ZIP_FL_ENC_GUESS);
                    scope(exit) zip_fclose(afile);

                    byte[] link_data;
                    ulong size_written = 0;
                    while (size_written != stat.size) {
                        byte[BUF_SIZE] chunk;
                        auto size_read = zip_fread(afile, &chunk, BUF_SIZE);
                        enforce!ZipException(
                            size_read > 0,
                            "Cannot read file %s. Read: %s/%s".format(
                                name, size_written, stat.size));
                        link_data ~= chunk[0 .. size_read];
                        size_written += size_read;
                    }
                    auto link_target = Path(cast(string) link_data);
                    enforce!ZipException(
                        link_target.isValid(),
                        "Cannot handle zip entry %s: the data '%s'(%s) is not valid path".format(
                            name, link_target, link_data));

                    // We have to ensure that parent directory created
                    dest.parent.mkdir(true);

                    link_target.symlink(dest);
                } else if (is_directory) {
                    // It it is directory, then we have to create one in destination.
                    dest.mkdir(true);
                } else {
                    // If it is file, then we have to extract file.

                    // ensure the directory for this file created.
                    dest.parent.mkdir(true);

                    auto out_file = dest.openFile("wb");
                    scope(exit) out_file.close();

                    auto afile = zip_fopen_index(
                        _zip_file.zip_ptr, _index, ZIP_FL_ENC_GUESS);
                    scope(exit) zip_fclose(afile);

                    ulong size_written = 0;
                    while (size_written != stat.size) {
                        byte[BUF_SIZE] buf;
                        auto size_read = zip_fread(afile, &buf, BUF_SIZE);
                        enforce!ZipException(
                            size_read > 0,
                            "Cannot read file %s. Read: %s/%s".format(
                                name, size_written, stat.size));
                        out_file.rawWrite(buf[0 .. size_read]);
                        size_written += size_read;
                    }
                }
            }
        }

        /// Initialize zip archive
        this(in Path path, in ZipMode mode = ZipMode.READONLY) {
            int error_code;
            auto zip_obj = zip_open(
                path.toStringz, mode, &error_code);
            scope(failure) zip_close(zip_obj);
            enforce!ZipException(
                !error_code,
                "Cannot open zip archive %s in mode %s: %s".format(
                    path, mode, format_zip_error(error_code)));
            _zipfile = ZipFile(zip_obj);
        }

        /// Get num entried
        auto num_entries() {
            return zip_get_num_entries(_zipfile.zip_ptr, ZIP_FL_ENC_GUESS);
        }

        /// Iterate over entries
        auto entries () {

            // Range iterator that allows to iterate over entries of zip archive
            struct ZipEntryIterator {
                private ZipFile _zip_file;
                private ulong _index;
                private ulong _max_entries;
                private Nullable!ZipEntry _entry;

                this(ZipFile zip_file, in ulong index=0) {
                    _zip_file = zip_file;
                    _index = index;
                    _max_entries = zip_get_num_entries(
                        _zip_file.zip_ptr, ZIP_FL_ENC_GUESS);
                }

                /** Check if iterator is consumed
                  **/
                bool empty() { return _index >= _max_entries; }

                /** Return front entry (if evalable)
                  **/
                auto front() {
                    if (_entry.isNull && _index < _max_entries)
                        _entry = ZipEntry(_zip_file, _index).nullable;
                    return _entry.get;
                }

                /** Pop front entry from iterator
                  **/
                void popFront() {
                    _entry.nullify;
                    _index++;
                }
            }

            return ZipEntryIterator(_zipfile);
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
