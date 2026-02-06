module odood.lib;

private import std.string: strip;

public immutable string _version = import("ODOOD_VERSION").strip;
public immutable bool is_dev_version = _version == "dev";

public import odood.lib.project;

