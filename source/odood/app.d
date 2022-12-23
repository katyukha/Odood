import std.stdio;
import std.format: format;

import odood.lib.exception: OdoodException;
import odood.cli.app;


/** Run CLI application
  **/
int main(string[] args) {
    auto program = new App();
    return program.run(args);
}

