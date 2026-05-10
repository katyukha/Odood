module odood.cli.core.exception;

private import std.exception: basicExceptionCtors;


/** Base class for all Odood CLI exceptions
  **/
class OdoodCLIException : Exception {
    mixin basicExceptionCtors;
}
