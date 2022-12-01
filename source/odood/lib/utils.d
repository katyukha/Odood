module odood.lib.utils;

private import std.process: execute, Config, Pid;
private import core.sys.posix.sys.types: pid_t;
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
            args, result.output));
    return result;
}

/// ditto
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
            args, result.output));
    return result;
}

/// Check if process is alive
bool isProcessRunning(in pid_t pid) {
    import core.sys.posix.signal: kill;
    import core.stdc.errno;

    int res = kill(pid, 0);
    if (res == -1 && errno == ESRCH)
        return false;
    return true;
}

/// ditto
bool isProcessRunning(scope Pid pid) {
    return isProcessRunning(pid.osHandle);
}
