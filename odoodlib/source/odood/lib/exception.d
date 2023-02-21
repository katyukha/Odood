module odood.lib.exception;

private import std.exception;


class OdoodException : Exception
{
    mixin basicExceptionCtors;
}
