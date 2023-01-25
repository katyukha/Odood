module odood.app;

import std.stdio;
import std.format: format;

import odood.lib.exception: OdoodException;
import odood.cli.app;


/** Run CLI application
  **/
int main(string[] args) {
    auto program = new App();

    version(odood_bash_autocomplete) {
        /* In case we need to generate bash autocompletition script,
         * we just want to print it to stdout. Letter it will be included in
         * debian package.
         */
        import commandr.completion.bash;

        write(program.createBashCompletionScript());
        return 0;
    } else {
        // Just run the program
        return program.run(args);
    }
}

