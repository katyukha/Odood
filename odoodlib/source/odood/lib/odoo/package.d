module odood.lib.odoo;

private import pyd.def: py_init;

// Initialize pyd as early as possible.
shared static this() {
    py_init();
}
