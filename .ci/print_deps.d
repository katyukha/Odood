#!/usr/bin/env dub

/+ dub.sdl:
    name "update_nfpm_deps"
    dependency "dyaml" version=">=0.9.2"
    dependency "darkcommand" version=">=0.0.5"
    dependency "thepath" version=">=0.0.8"
+/

/* This script updates nfpm spec with correct dependencies.
 * It is needed to keep single list of deb dependencies, without duplication.
 */

import darkcommand;
import dyaml;
import thepath;
import std.stdio;

class PrintDepsProgram : Program {
    this() {
        super("print-deps", "1.0.0");
        this.summary("Print list of dependencies.");
    }

    override int execute() {
        Node config = dyaml.Loader.fromFile(
            Path.current.join("nfpm.yaml").toString).load();
        foreach(Node dep; config["depends"])
            writeln(dep.as!string);
        return 0;
    }
}

int main(string[] argv) {
    return new PrintDepsProgram().run(argv);
}
