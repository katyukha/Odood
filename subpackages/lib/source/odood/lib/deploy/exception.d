module odood.lib.deploy.exception;

private import std.exception: basicExceptionCtors;

private import odood.exception: OdoodException;


class OdoodDeployException : OdoodException {
    mixin basicExceptionCtors;
}

