module odood.utils.zipper.zipper;

private import std.typecons;
private import std.exception: enforce;
private import std.string: toStringz;
private import std.format: format;

private import deimos.zip;

private import thepath: Path;

private import odood.utils.zipper;
private import odood.utils.zipper.entry;
private import odood.utils.zipper.internal;
private import odood.utils.zipper.exception;


struct Zipper {

    private:
        ZipPtr _zip_ptr;

        /// locate entry index by name
        auto locateByName(in string name) {
            // TODO: Handle errors (ZIP_ER_INVAL, ZIP_ER_MEMORY, ZIP_ER_NOENT)
            // See: https://libzip.org/documentation/zip_name_locate.html#ERRORS
            return zip_name_locate(
                _zip_ptr.zip_ptr, name.toStringz, ZIP_FL_ENC_GUESS);
        }
    public:
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
            _zip_ptr = ZipPtr(zip_obj);
        }

        /// Get num entried
        auto num_entries() {
            return zip_get_num_entries(_zip_ptr.zip_ptr, ZIP_FL_ENC_GUESS);
        }

        /// Iterate over entries
        auto entries () {

            // Range iterator that allows to iterate over entries of zip archive
            struct ZipEntryIterator {
                private ZipPtr _zip_ptr;
                private ulong _index;
                private ulong _max_entries;
                private Nullable!ZipEntry _entry;

                this(ZipPtr zip_file, in ulong index=0) {
                    _zip_ptr = zip_file;
                    _index = index;
                    _max_entries = zip_get_num_entries(
                        _zip_ptr.zip_ptr, ZIP_FL_ENC_GUESS);
                }

                /** Check if iterator is consumed
                  **/
                bool empty() { return _index >= _max_entries; }

                /** Return front entry (if evalable)
                  **/
                auto front() {
                    if (_entry.isNull && _index < _max_entries)
                        _entry = ZipEntry(_zip_ptr, _index).nullable;
                    return _entry.get;
                }

                /** Pop front entry from iterator
                  **/
                void popFront() {
                    _entry.nullify;
                    _index++;
                }
            }

            return ZipEntryIterator(_zip_ptr);
        }

        /// Get entry by index or name
        auto entry(in ulong index) {
            return ZipEntry(_zip_ptr, index);
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

