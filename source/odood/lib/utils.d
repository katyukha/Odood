module odood.lib.utils;

private import std.process: execute, Config;
private import std.exception: enforce;
private import std.format: format;

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
