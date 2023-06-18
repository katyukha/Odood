module odood.utils.zip;

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

private import odood.exception: OdoodException;

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

        /// locate entry index by name
        auto locateByName(in string name) {
            // TODO: Handle errors (ZIP_ER_INVAL, ZIP_ER_MEMORY, ZIP_ER_NOENT)
            // See: https://libzip.org/documentation/zip_name_locate.html#ERRORS
            return zip_name_locate(
                _zipfile.zip_ptr, name.toStringz, ZIP_FL_ENC_GUESS);
        }
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

            /** Read zip entry by char (raw), do not resolve symlinks
              **/
            private void readRawByChunk(T=byte)(
                    void delegate(scope const T[] chunk,
                                  in ulong chunk_size) dg) {
                enforce!ZipException(
                    !is_directory,
                    "readRawByChunk could be applied only to files " ~
                    "and symlinks, and not directories!");
                auto afile = zip_fopen_index(
                    _zip_file.zip_ptr, _index, ZIP_FL_ENC_GUESS);
                scope(exit) zip_fclose(afile);

                ulong total_size_read = 0;
                while (total_size_read < stat.size) {
                    T[BUF_SIZE] buf;
                    auto size_read = zip_fread(afile, &buf, BUF_SIZE);
                    enforce!ZipException(
                        size_read > 0,
                        "Cannot read file %s. Read: %s/%s".format(
                            name, total_size_read, stat.size));
                    // Pass data read to delegate
                    dg(buf[], size_read);
                    total_size_read += size_read;
                }
                enforce!ZipException(
                    total_size_read == stat.size,
                    "Cannot read file %s. Read: %s instead of %s bytes".format(
                        name, total_size_read, stat.size));
            }
            /** Read raw entry data (as is).
              *
              * Note, in case of symlinks, this method will return
              * the target of the symlink, not the content.
              **/
            private T[] readRawFull(T=byte)() {
                T[] result;
                readRawByChunk!T(
                    (scope const T[] chunk, in ulong chunk_size) {
                        result ~= chunk[0 .. chunk_size];
                    });
                return result;
            }

            /** Read the target of the link
              **/
            Path readLink() {
                enforce!ZipException(
                    is_symlink,
                    "readLink could be applied only on symlinks!");
                char[] link_data = readRawFull!char;
                return Path(cast(string) link_data);
            }

            /** Resolve symlink.
              *
              * Returns: ZipEntry that is target of symlink.
              **/
            ZipEntry resolveLink() {
                auto target = readLink;
                auto target_resolved = Path(_name).parent(false).join(target).normalize;
                auto target_index = zip_name_locate(
                    _zip_file.zip_ptr, target_resolved.toStringz, ZIP_FL_ENC_GUESS);
                enforce!ZipException(
                    target_index >= 0,
                    "Cannot locate symlink (%s) target (%s resolved to %s) " ~
                    "in archive!".format(
                        name, target, target_resolved));
                return ZipEntry(_zip_file, target_index);
            }

            /** Read complete file from zip archive.
              *
              * In case when applied to symlink, it will be automatically
              * resolved.
              **/
            T[] readFull(T=byte)() {
                if (is_symlink)
                    return resolveLink.readFull!T;

                enforce!ZipException(
                    !is_directory,
                    "readRaw could be applied only to files and symlinks, " ~
                    "not directories and not symlinks!");
                return readRawFull!T;
            }

            /** Read file by chunks
              *
              * Applicable only to files. On attempt to read directory
              * will throw ZipException.
              *
              * On attempt to read symlink, content of link target entry
              * will be read.
              *
              * Throws: ZipException when cannot read enough data,
              *    or if read too much data.
              *
              **/
            void readByChunk(T=byte)(
                    void delegate(scope const T[] chunk,
                                  in ulong chunk_size) dg) {
                if (is_symlink)
                    return resolveLink.readByChunk!T(dg);

                enforce!ZipException(
                    !is_directory && !is_symlink,
                    "readByChunk could be applied only to files, " ~
                    "not symlinks and not directories!");

                readRawByChunk!T(dg);
            }

            /** Unzip entry to specified path
              *
              * Params:
              *     dest = destination path to unzip entry
              **/
            void unzipTo(in Path dest) {
                if (is_symlink) {
                    auto link_target = readLink;
                    enforce!ZipException(
                        link_target.isValid(),
                        "Cannot handle zip entry %s: the link target '%s' " ~
                        " is not valid path".format(name, link_target));

                    // We have to ensure that parent directory created
                    dest.parent.mkdir(true);

                    link_target.symlink(dest);
                } else if (is_directory) {
                    // It it is directory, then we have to create one in destination.
                    // TODO: Do we need to unzip content of the directory?
                    // TODO: Do we need to create dest dir here?
                    dest.mkdir(true);
                } else {
                    // If it is file, then we have to extract file.

                    // ensure the directory for this file created.
                    dest.parent.mkdir(true);

                    auto out_file = dest.openFile("wb");
                    scope(exit) out_file.close();

                    readByChunk(
                        (scope const byte[] chunk, in ulong chunk_size) {
                            out_file.rawWrite(chunk[0 .. chunk_size]);
                        });
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

        /// Get entry by index or name
        auto entry(in ulong index) {
            return ZipEntry(_zipfile, index);
        }

        // TODO: Handle Path as a key for entry
        /// ditto
        auto entry(in string name) {
            auto index = locateByName(name);
            enforce!ZipException(
                index != -1,
                "Cannot locate %s in zip archive!".format(name));
            return entry(index);
        }

        /// Check if zip archive contains entry
        bool hasEntry(in string name) {
            auto index = locateByName(name);
            // if index is equal to -1, then such entry was not found
            return index >= 0;
        }

        /// Operator overload to easier access entries
        auto opIndex(in ulong index) {
            return entry(index);
        }

        /// ditto
        auto opIndex(in string name) {
            return entry(name);
        }
}

/// Example of unarchiving archive
unittest {
    import unit_threaded.assertions;

    // Zipfile will be closed automatically when zip is out of scope.
    auto zip = Zipper(Path("test-data", "test-zip.zip"));

    zip.num_entries.shouldEqual(7);

    zip.hasEntry("test-zip/").shouldBeTrue();
    zip["test-zip/"].is_directory.shouldBeTrue();

    zip.hasEntry("test-zip/test.txt").shouldBeTrue();
    zip["test-zip/test.txt"].is_symlink.shouldBeFalse();
    zip["test-zip/test.txt"].readFull!char.shouldEqual("Test Root\n");

    zip.hasEntry("test-zip/test-dir/test.txt").shouldBeTrue();
    zip["test-zip/test-dir/test.txt"].is_symlink.shouldBeFalse();
    zip["test-zip/test-dir/test.txt"].readFull!char.shouldEqual("Hello World!\n");

    zip.hasEntry("test-zip/test-link-1.txt").shouldBeTrue();
    zip["test-zip/test-link-1.txt"].is_symlink.shouldBeTrue();
    zip["test-zip/test-link-1.txt"].readLink.shouldEqual(Path("test-dir", "test.txt"));
    zip["test-zip/test-link-1.txt"].readFull!char.shouldEqual("Hello World!\n");

    zip.hasEntry("test-zip/test-dir/test-link.txt").shouldBeTrue();
    zip["test-zip/test-dir/test-link.txt"].is_symlink.shouldBeTrue();
    zip["test-zip/test-dir/test-link.txt"].readLink.shouldEqual(Path("test.txt"));
    zip["test-zip/test-dir/test-link.txt"].readFull!char.shouldEqual("Hello World!\n");

    zip.hasEntry("test-zip/test-dir/test-parent.txt").shouldBeTrue();
    zip["test-zip/test-dir/test-parent.txt"].is_symlink.shouldBeTrue();
    zip["test-zip/test-dir/test-parent.txt"].readLink.shouldEqual(Path("..", "test.txt"));
    zip["test-zip/test-dir/test-parent.txt"].readFull!char.shouldEqual("Test Root\n");
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
