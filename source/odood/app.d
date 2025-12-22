module odood.app;

import std.stdio: write;
import std.format: format;

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
        /* In case we need to generate bash autocompletition script,
         * we just want to print it to stdout. Letter it will be included in
         * debian package.
         */
        import commandr.completion.bash;

        write(program.createBashCompletionScript());
        return 0;
    } else version(odood_docs_command_ref_generator) {
        import commandr.program;
        import commandr.help;
        import std.stdio: write, writeln, writefln;
        import std.array: join;

        void generateDocsCommandRef(Command command) {
            if (cast(Program)command)
                writefln("## `%s`\n", command.name);
            else
                writefln("### `%s`\n", command.chain.join(" "));

            writeln("```");
            printHelp(command);
            writeln("```");

            foreach(cmd; command.commands) {
                generateDocsCommandRef(cmd);
            }
        }
        writeln("# Odood Command Reference\n");
        writeln("This page lists all commands available in Odood and their help messages.");
        generateDocsCommandRef(program);
        return 0;
    } else {
        // Just run the program
        return program.run(args);
    }
}

