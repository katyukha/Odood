/** Module to easily run and interact with other processes
  **/
// TODO: Move to separate package (out of Odood)
module odood.utils.theprocess;

private import std.format;
private import std.process;
private import std.file;
private import std.stdio;
private import std.exception;
private import std.string: join;
private import std.typecons;

version(Posix) {
    private import core.sys.posix.unistd;
    private import core.sys.posix.pwd;
}

private import thepath;


/** Resolve program name according to system path
  *
  * Params:
  *     name = name of program to find
  * Returns:
  *     Nullable!Path to program.
  **/
@safe Nullable!Path resolveProgram(in string program) {
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


/** Process result, produced by 'execute' method of Process.
  **/
@safe const struct ProcessResult {
    private string _program;
    private string[] _args;

    /// exit code of the process
    int status;

    /// text output of the process
    string output;

    // Do not allow to create records without params
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


/** This struct is used to prepare configuration for process and run it.
  *
  * Following ways to run process supported:
  * - execute: run process and catch its output and exit code
  * - spawn: spawn the process in background, and optionally pip its output.
  * - pipe: spawn the process and attach configurable pipes to catch output.
  *
  * The configuration of process to run performend in following a way:
  * 1. Create the Process instance specifying the program to run
  * 2. Apply desired configuration (args, env, workDir)
  *    via calls to corresponding methods.
  * 3. Run one of `execute`, `spawn` or `pipe` method, that will do actual
  *    start of the process.
  *
  * Configuration methods usually prefixed with `set` word, but also,
  * they have semantic aliases. For example, method `setArgs` also has
  * alias `withArgs`, and method `setWorkDir` has alias `inWorkDir`.
  * Additionally, configuration methods always
  * return the reference to current instance of the Process being configured.
  *
  * Examples:
  * ---
  * // It is possible to run process in following way:
  * auto result = Process('my-program')
  *         .withArgs("--verbose", "--help")
  *         .withEnv("MY_ENV_VAR", "MY_VALUE")
  *         .inWorkDir("my/working/directory")
  *         .execute()
  *         .ensureStatus!MyException("My error message on failure");
  * writeln(result.output);
  * ---
  * // Also, in Posix system it is possible to run command as different user:
  * auto result = Process('my-program')
  *         .withUser("bob")
  *         .execute()
  *         .ensureStatus!MyException("My error message on failure");
  * writeln(result.output);
  * ---
  **/
@safe struct Process {
    private string _program;
    private string[] _args;
    private string[string] _env=null;
    private string _workdir=null;
    private std.process.Config _config=std.process.Config.none;

    version(Posix) {
        /* On posix we have ability to run process with different user,
         * thus we have to keep desired uid/gid to run process with and
         * original uid/git to revert uid/gid change after process completed.
         */
        private Nullable!uid_t _uid;
        private Nullable!gid_t _gid;
        private Nullable!uid_t _original_uid;
        private Nullable!gid_t _original_gid;
    }

    /** Create new Process instance to run specified program.
      *
      * Params:
      *     program = name of program to run or path of program to run
      **/
    this(in string program) {
        _program = program;
    }

    /// ditto
    this(in Path program) {
        _program = program.toAbsolute.toString;
    }

    /** Return string representation of process to be started
      **/
    string toString() const {
        return "Program: %s, args: %s, env: %s, workdir: %s".format(
            _program, _args.join(" "), _env, _workdir);
    }

    /** Set arguments for the process
      *
      * Params:
      *     args = array of arguments to run program with
      *
      * Returns:
      *     reference to this (process instance)
      **/
    auto ref setArgs(in string[] args...) {
        _args = args.dup;
        return this;
    }

    /// ditto
    alias withArgs = setArgs;

    /** Add arguments to the process.
      *
      * This could be used if you do not know all the arguments for program
      * to run at single point, and you need to add it conditionally.
      *
      * Params:
      *     args = array of arguments to run program with
      *
      * Returns:
      *     reference to this (process instance)
      *
      * Examples:
      * ---
      * auto program = Process('my-program')
      *     .withArgs("--some-option");
      *
      * if (some condition)
      *     program.addArgs("--some-other-opt", "--verbose");
      *
      * auto result = program
      *     .execute()
      *     .ensureStatus!MyException("My error message on failure");
      * writeln(result.output);
      * ---
      **/
    auto ref addArgs(in string[] args...) {
        _args ~= args;
        return this;
    }

    /** Set work directory for the process to be started
      *
      * Params:
      *     workdir = working directory path to run process in
      *
      * Returns:
      *     reference to this (process instance)
      *
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
      *
      * Params:
      *     env = associative array to update environment to run process with.
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    auto ref setEnv(in string[string] env) {
        foreach(i; env.byKeyValue)
            _env[i.key] = i.value;
        return this;
    }

    /** Set environment variable (specified by key) to provided value
      *
      * Params:
      *     key = environment variable name
      *     value = environment variable value
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
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

    /** Set UID to run process with
      *
      * Params:
      *     uid = UID (id of system user) to run process with
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    version(Posix) auto ref setUID(in uid_t uid) {
        _uid = uid;
        return this;
    }

    /// ditto
    version(Posix) alias withUID = setUID;

    /** Set GID to run process with
      *
      * Params:
      *     gid = GID (id of system group) to run process with
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    version(Posix) auto ref setGID(in gid_t gid) {
        _gid = gid;
        return this;
    }

    /// ditto
    version(Posix) alias withGID = setGID;

    /** Run process as specified user
      *
      * If this method applied, then the UID and GID to run process with
      * will be taked from record in passwd database
      *
      * Params:
      *     username = login of user to run process as
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    version(Posix) auto ref setUser(in string username) @trusted {
        import std.string: toStringz;

        /* pw info has following fields:
         *     - pw_name,
         *     - pw_passwd,
         *     - pw_uid,
         *     - pw_gid,
         *     - pw_gecos,
         *     - pw_dir,
         *     - pw_shell,
         */
        auto pw = getpwnam(username.toStringz);
        errnoEnforce(
            pw !is null,
            "Cannot get info about user %s".format(username));
        setUID(pw.pw_uid);
        setGID(pw.pw_gid);
        // TODO: add ability to automatically set user's home directory
        //       if needed
        return this;
    }

    ///
    version(Posix) alias withUser = setUser;

    /// Called before running process to run pre-exec hooks;
    private void setUpProcess() {
        version(Posix) {
            /* We set real user and real group here,
             * keeping original effective user and effective group
             * (usually original user/group is root, when such logic used)
             * Later in preExecFunction, we can update effective user
             * for child process to be same as real user.
             * This is needed, because bash, changes effective user to real
             * user when effective user is different from real.
             * Thus, we have to set both real user and effective user
             * for child process.
             *
             * We can accomplish this in two steps:
             *     - Change real uid/gid here for current process
             *     - Change effective uid/gid to match real uid/gid
             *       in preexec fuction.
             * Because preexec function is executed in child process,
             * that will be replaced by specified command proces, it works.
             *
             * Also, note, that first we have to change group ID, because
             * when we change user id first, it may not be possible to change
             * group.
             */

             /*
              * TODO: May be it have sense to change effective user/group
              *       instead of real user, and update real user in
              *       child process.
              */
            if (!_gid.isNull && _gid.get != getgid) {
                _original_gid = getgid().nullable;
                errnoEnforce(
                    setregid(_gid.get, -1) == 0,
                    "Cannot set real GID to %s before starting process: %s".format(
                        _gid, this.toString));
            }
            if (!_uid.isNull && _uid.get != getuid) {
                _original_uid = getuid().nullable;
                errnoEnforce(
                    setreuid(_uid.get, -1) == 0,
                    "Cannot set real UID to %s before starting process: %s".format(
                        _uid, this.toString));
            }

            if (!_original_uid.isNull || !_original_gid.isNull)
                _config.preExecFunction = () @trusted nothrow @nogc {
                    /* Because we cannot pass any parameters here,
                     * we just need to make real user/group equal to
                     * effective user/group for child proces.
                     * This is needed, because bash could change effective user
                     * when it is different from real user.
                     *
                     * We change here effective user/group equal
                     * to real user/group because we have changed
                     * real user/group in parent process
                     * before running this function.
                     *
                     * Also, note, that this function will be executed
                     * in child process, just before calling execve.
                     */
                    if (setegid(getgid) != 0)
                        return false;
                    if (seteuid(getuid) != 0)
                        return false;
                    return true;
                };

        }
    }

    /// Called after process started to run post-exec hooks;
    private void tearDownProcess() {
        version(Posix) {
            // Restore original uid/gid after process started.
            if (!_original_gid.isNull)
                errnoEnforce(
                    setregid(_original_gid.get, -1) == 0,
                    "Cannot restore real GID to %s after process started: %s".format(
                        _original_gid, this.toString));
            if (!_original_uid.isNull)
                errnoEnforce(
                    setreuid(_original_uid.get, -1) == 0,
                    "Cannot restore real UID to %s after process started: %s".format(
                        _original_uid, this.toString));
        }
    }

    /** Execute the configured process and capture output.
      *
      * Params:
      *     max_output = max size of output to capture.
      *
      * Returns:
      *     ProcessResult instance that contains output and exit-code
      *     of program
      *
      **/
    auto execute(in size_t max_output=size_t.max) {
        setUpProcess();
        auto res = std.process.execute(
            [_program] ~ _args,
            _env,
            _config,
            max_output,
            _workdir);
        tearDownProcess();
        return ProcessResult(_program, _args, res.status, res.output);
    }

    /// Spawn process
    auto spawn(File stdin=std.stdio.stdin,
               File stdout=std.stdio.stdout,
               File stderr=std.stdio.stderr) {
        setUpProcess();
        auto res = std.process.spawnProcess(
            [_program] ~ _args,
            stdin,
            stdout,
            stderr,
            _env,
            _config,
            _workdir);
        tearDownProcess();
        return res;
    }

    /// Pipe process
    auto pipe(in Redirect redirect=Redirect.all) {
        setUpProcess();
        auto res = std.process.pipeProcess(
            [_program] ~ _args,
            redirect,
            _env,
            _config,
            _workdir);
        tearDownProcess();
        return res;
    }
}


// Test simple api
@safe unittest {
    import unit_threaded.assertions;

    auto process = Process("my-program")
        .withArgs("--verbose", "--help")
        .withEnv("MY_VAR", "42")
        .inWorkDir("/my/path");
    process._program.should == "my-program";
    process._args.should == ["--verbose", "--help"];
    process._env.should == ["MY_VAR": "42"];
    process._workdir.should == "/my/path";
    process.toString.should ==
        "Program: %s, args: %s, env: %s, workdir: %s".format(
            process._program, process._args.join(" "),
            process._env, process._workdir);
}
