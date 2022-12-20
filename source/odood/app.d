import std.stdio;
import std.format: format;

import odood.lib.exception: OdoodException;
import odood.cli.app;


int main(string[] args) {
    auto program = new App();

    try {
        return program.run(args);
    } catch (OdoodException e) {
        writeln("Odood Exception catched: %s".format(e));
        return 1;
    } catch (Exception e) {
        writeln("Exception catched: %s".format(e));
        return 1;
    }
}

