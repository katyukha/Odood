#!/usr/bin/env dub

/+ dub.sdl:
    name "update_nfpm_deps"
    dependency "dyaml" version=">=0.9.2"
    dependency "commandr" version=">=1.1.0"
    dependency "thepath" version=">=0.0.8"
+/

/* This script updates nfpm spec with correct dependencies.
 * It is needed to keep single list of deb dependencies, without duplication.
 */

import commandr;
import dyaml;
import thepath;
import std.stdio;

void main(string[] argv) {
    auto args = new Program("Print deps")
        .summary("Print list of dependencies.")
        .parse(argv);

    Node config = dyaml.Loader.fromFile(Path.current.join("nfpm.yaml").toString).load();
    foreach(Node dep; config["depends"])
        writeln(dep.as!string);
}
