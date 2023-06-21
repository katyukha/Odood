module odood.utils.zipper.internal;

private import std.typecons;
private import std.string: fromStringz;

private import deimos.zip;

immutable BUF_SIZE = 1024;

enum ZipMode {
    CREATE = ZIP_CREATE,
    EXCLUSIVE = ZIP_EXCL,
    TRUNCATE = ZIP_TRUNCATE,
    READONLY = ZIP_RDONLY,
    CHECK_CONSISTENCY = ZIP_CHECKCONS,
};

package:

    /** Payload of ref-counted struct for zip-archive pointer
      **/
    private struct ZipPtrInternal {
        private zip_t* _zip_ptr;

        this(zip_t* zip_ptr) {
            this._zip_ptr = zip_ptr;
        }

        ~this() {
            if (_zip_ptr !is null) {
                zip_close(_zip_ptr);
                _zip_ptr = null;
            }
        }

        // Must not be copiable
        @disable this(this);

        // Must not be assignable
        @disable void opAssign(typeof(this));

        zip_t* zip_ptr() { return _zip_ptr; }

        // getErrorMsg
        auto getErrorMsg() {
            auto error_msg = zip_error_strerror(
                zip_get_error(_zip_ptr)
            ).fromStringz;
            return error_msg;
        }
    }

    /// Ref-counted pointer to zip archive
    alias RefCounted!(ZipPtrInternal, RefCountedAutoInitialize.no) ZipPtr;
