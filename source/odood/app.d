module odood.app;

import std.stdio;
import std.format: format;

import odood.exception: OdoodException;
import odood.cli.app;

version(OdoodUnittestIntegrationUT) {
    import unit_threaded;
    mixin runTestsMain!(
        //"odood",
        //"odood.app",
        //"odood.exception",
        //"odood.utils",
        //"odood.utils.zip",
        //"odood.lib",
        //"odood.cli",
        "tests.basic",
    );

/** Run CLI application
  **/
} else int main(string[] args) {
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

