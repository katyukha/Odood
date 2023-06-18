module odood.utils.zipper.entry;

private import std.typecons;
private import std.datetime.systime;
private import std.format: format;
private import std.exception: enforce;
private import std.string: toStringz, fromStringz, strip;
private import std.algorithm.searching: endsWith;

private import deimos.zip;

private import thepath: Path;

private import odood.utils.zipper.zipper;
private import odood.utils.zipper.internal;
private import odood.utils.zipper.exception;


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
    private ZipPtr _zip_file;
    private ulong _index;
    private string _name;
    private Nullable!ZipEntryStat _stat;
    private Nullable!uint _attributes;

    @disable this();

    this(ZipPtr zip_file, in ulong index) {
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
