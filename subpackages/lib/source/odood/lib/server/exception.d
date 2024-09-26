module odood.lib.server.exception;

private import std.exception: basicExceptionCtors;
private import odood.exception: OdoodException;


class ServerException : OdoodException
{
    mixin basicExceptionCtors;
}


class ServerAlreadyRuningException : ServerException
{
    mixin basicExceptionCtors;
}
