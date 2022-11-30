module odood.lib.utils;

private import std.process: execute, Config;
private import std.exception: enforce;
private import std.format: format;

private import thepath: Path;

private import odood.lib.exception: OdoodException;


/// Run command. Same as std.process.execute, with different order of arguments.
@safe auto runCmd(
        scope const(char[])[] args,
        scope const(char)[] workDir = null,
        const string[string] env = null,
        Config config = Config.none,
        size_t maxOutput = size_t.max) {
    return execute(args, env, config, maxOutput, workDir); 
}

/// ditto
auto runCmd(
        in Path path,
        in string[] args = [],
        in Path workDir = Path(),
        in string[string] env = null,
        in Config config = Config.none,
        in size_t maxOutput = size_t.max) {

    return path.execute(args, env, workDir, config, maxOutput);
}


/// Run command raising exception for non-zero return code
auto runCmdE(
        scope const(char[])[] args,                        
        scope const(char)[] workDir = null,                
        const string[string] env = null,
        Config config = Config.none,                       
        size_t maxOutput = size_t.max) {                   

    auto result = execute(args, env, config, maxOutput, workDir); 
    enforce!OdoodException(
        result.status == 0,
        "Command %s returned non-zero error code!\nOutput: %s".format(
            args, result.status));
    return result;
}

///
auto runCmdE(
        in Path path,
        in string[] args = [],
        in Path workDir = Path(),
        in string[string] env = null,
        in Config config = Config.none,
        in size_t maxOutput = size_t.max) {

    auto result = path.execute(args, env, workDir, config, maxOutput);
    enforce!OdoodException(
        result.status == 0,
        "Command %s returned non-zero error code!\nOutput: %s".format(
            args, result.status));
    return result;
}
