module odood.lib;

public immutable string _version = "0.0.5-dev";

public import odood.lib.project;


// Initialize pyd as early as possible.
shared static this() {
    import pyd.def: py_init;
    py_init();
}
