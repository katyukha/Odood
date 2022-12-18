import std.stdio;
import std.format: format;

import odood.cli: OdoodProgram;
import odood.lib.exception: OdoodException, OdoodExitException;

int main(string[] args) {
    auto program = new OdoodProgram();

    try {
        program.run(args);
    } catch (OdoodExitException e) {
        return e.exit_code;
    } catch (OdoodException e) {
        writeln("Odood Exception catched: %s".format(e));
        return 1;
    } catch (Exception e) {
        writeln("Exception catched: %s".format(e));
        return 1;
    }
    return 0;
}
