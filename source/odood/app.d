module odood.app;

import odood.exception: OdoodException;
import odood.cli.app: App;

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
        import std.stdio: stdout;
        program.generateBashCompletion(stdout);
        return 0;
    } else version(odood_docs_command_ref_generator) {
        import std.stdio: stdout;
        program.generateMarkdownDocs(stdout);
        return 0;
    } else {
        // Just run the program
        return program.run(args);
    }
}

