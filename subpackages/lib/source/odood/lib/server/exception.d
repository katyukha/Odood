module odood.lib.server.exception;

private import std.exception;
private import odood.lib.exception: OdoodException;


class ServerException : OdoodException
{
    mixin basicExceptionCtors;
}


class ServerAlreadyRuningException : OdoodException
{
    mixin basicExceptionCtors;
}

