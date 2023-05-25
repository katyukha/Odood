/** Module to easily run and interact with other processes
  **/
// TODO: Move to separate package (out of Odood)
module odood.lib.theprocess;

private import std.format;
private import std.process;
private import std.file;
private import std.stdio;
private import std.exception;
private import std.string: join;
private import std.typecons;

private import thepath;


/** Resolve program name according to system path
  *
  * Params:
  *     name = name of program to find
  * Returns:
  *     Nullable path to program.
  **/
Nullable!Path resolveProgram(in string program) {
    import std.path: pathSeparator;
    import std.array: split;
    foreach(sys_path; environment["PATH"].split(pathSeparator)) {
        auto sys_program_path = Path(sys_path).join(program);
        if (!sys_program_path.exists)
            continue;

        // TODO: check with lstat if link is not broken
        return sys_program_path.nullable;
    }
    return Nullable!Path.init;
}

///
version(Posix) unittest {
    import unit_threaded.assertions;

    resolveProgram("sh").isNull.shouldBeFalse;
    resolveProgram("sh").get.toString.shouldEqual("/usr/bin/sh");

    resolveProgram("unexisting_program").isNull.shouldBeTrue;
}


/// Exception to be raise by Process struct
class ProcessException : Exception
{
    mixin basicExceptionCtors;
}


// TODO: Make it immutable
@safe const struct ProcessResult {
    private string _program;
    private string[] _args;

    int status;
    string output;

    @disable this();

    private pure this(
            in string program,
            in string[] args,
            in int status,
            in string output) nothrow {
        this._program = program;
        this._args = args;
        this.status = status;
        this.output = output;
    }

    /** Ensure that program exited with expected exit code
      *
      * Params:
      *     msg = message to throw in exception in case of check failure
      *     expected = expected exit-code, if differ, then
      *         exception will be thrown.
      **/
    auto ref ensureStatus(E : Throwable = ProcessException)(
            in string msg, in int expected=0) const {
        enforce!E(status == expected, msg);
        return this;
    }

    /// ditto
    auto ref ensureStatus(E : Throwable = ProcessException)(in int expected=0) const {
        return ensureStatus(
            "Program %s with args %s failed! Expected exit code %s, got %s.\nOutput: %s".format(
                _program, _args, expected, status, output),
            expected);
    }
}


@safe struct Process {
    private string _program;
    private string[] _args;
    private string[string] _env=null;
    private string _workdir=null;
    private std.process.Config _config=std.process.Config.none;

    this(in string program) {
        _program = program;
    }

    this(in Path program) {
        _program = program.toAbsolute.toString;
    }

    string toString() {
        return "Program: %s, args: %s, env: %s, workdir: %s".format(
            _program, _args.join(" "), _env, _workdir);
    }

    /** Set arguments for the process
      **/
    auto ref setArgs(in string[] args...) {
        _args = args.dup;
        return this;
    }

    /// ditto
    alias withArgs = setArgs;

    /** Add arguments to the process
      **/
    auto ref addArgs(in string[] args...) {
        _args ~= args;
        return this;
    }

    /** Set work directory for the process to be started
      **/
    auto ref setWorkDir(in string workdir) {
        _workdir = workdir;
        return this;
    }

    /// ditto
    auto ref setWorkDir(in Path workdir) {
        _workdir = workdir.toString;
        return this;
    }

    /// ditto
    alias inWorkDir = setWorkDir;

    /** Set environemnt for the process to be started
      **/
    auto ref setEnv(in string[string] env) {
        foreach(i; env.byKeyValue)
            _env[i.key] = i.value;
        return this;
    }

    /// ditto
    auto ref setEnv(in string key, in string value) {
        _env[key] = value;
        return this;
    }

    /// ditto
    alias withEnv = setEnv;

    /** Set process configuration
      **/
    auto ref setConfig(in std.process.Config config) {
        _config = config;
        return this;
    }

    /// ditto
    alias withConfig = setConfig;

    /** Set configuration flag for process to be started
      **/
    auto ref setFlag(in std.process.Config.Flags flag) {
        _config.flags |= flag;
        return this;
    }

    /// ditto
    auto ref setFlag(in std.process.Config flags) {
        _config |= flags;
        return this;
    }

    /// ditto
    alias withFlag = setFlag;

    /// Execute program
    auto execute(in size_t max_output=size_t.max) {
        auto res = std.process.execute(
            [_program] ~ _args,
            _env,
            _config,
            max_output,
            _workdir);
        return ProcessResult(_program, _args, res.status, res.output);
    }

    /// Spawn process
    auto spawn(File stdin=std.stdio.stdin,
               File stdout=std.stdio.stdout,
               File stderr=std.stdio.stderr) {
        return std.process.spawnProcess(
            [_program] ~ _args,
            stdin,
            stdout,
            stderr,
            _env,
            _config,
            _workdir);
    }

    /// Pipe process
    auto pipe(in Redirect redirect=Redirect.all) {
        return std.process.pipeProcess(
            [_program] ~ _args,
            redirect,
            _env,
            _config,
            _workdir);
    }
}
