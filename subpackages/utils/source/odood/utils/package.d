module odood.utils;

/** This package contains various utilities that do not depend on Odoo project.
  * Thus, they could be used in other projects that do not use Odood projects.
  **/

private import core.time: Duration, seconds;
private import core.sys.posix.sys.types: pid_t;
private import core.thread: Thread;
private import std.logger: warningf;
private import std.process: Pid;
private import std.exception: enforce, basicExceptionCtors;
private import std.format: format;
private import std.random: uniform;
private import std.typecons: Nullable, nullable;
private import std.regex: ctRegex, matchFirst;

private import thepath: Path;
private import theprocess: Process;

private import odood.exception: OdoodException;
private import odood.utils.versioned: Version;


/** Parse python version
  *
  * Params:
  *     project = instance of Odood project to get version of system python for.
  * Returns: SemVer version of system python interpreter
  **/
package(odood) @safe Version parsePythonVersion(in Path interpreter_path) {
    auto python_version_raw = Process(interpreter_path)
        .withArgs("--version")
        .execute()
        .ensureStatus(
            "Cannot get version of python interpreter '%s'".format(
                interpreter_path))
        .output;

    immutable auto re_py_version = ctRegex!(`Python (\d+.\d+.\d+)`);
    auto re_match = python_version_raw.matchFirst(re_py_version);
    enforce!OdoodException(
        !re_match.empty,
        "Cannot parse python interpreter (%s) version '%s'".format(
            interpreter_path, python_version_raw));
    return Version(re_match[1]);
}


/// Check if process is alive
bool isProcessRunning(in pid_t pid) {
    import core.sys.posix.signal: kill;
    import core.stdc.errno;

    const int res = kill(pid, 0);
    if (res == -1 && errno == ESRCH)
        return false;
    return true;
}

/// ditto
bool isProcessRunning(scope Pid pid) {
    return isProcessRunning(pid.osHandle);
}


/** This exeption will be raised when it is not possible to download the file
  **/
class OdoodDownloadException : OdoodException
{
    mixin basicExceptionCtors;
}


/** Download the file from the web
  *
  * Params:
  *     url = the url to download file from
  *     dest_path = the destination path to download file to
  *     timeout = optional timeout. Default is 15 seconds.
  *     max_retries = optional max numer of retries in case of ConnectError.
  **/
void download(
        in string url,
        in Path dest_path,
        in Duration timeout=15.seconds,
        in ubyte max_retries=3) {
    import requests: Request, Response, RequestException;
    import requests.streams: ConnectError, TimeoutException, NetworkException;

    enforce!OdoodDownloadException(
        !dest_path.exists,
        "Cannot download %s to %s! Destination path already exists!".format(
            url, dest_path));

    for(ubyte attempt = 0; attempt <= max_retries; ++attempt) {
        try {
            auto request = Request();
            request.useStreaming = true;
            request.timeout = timeout;

            auto response = request.get(url);
            auto stream = response.receiveAsRange();

            auto f_dest = dest_path.openFile("wb");
            scope(exit) f_dest.close();

            while (!stream.empty) {
                f_dest.rawWrite(stream.front);
                stream.popFront;
            }
        } catch (Exception e) {
            // If exception is not retriable, just reraise it.
            if (!(cast(RequestException)e ||
                    cast(ConnectError)e ||
                    cast(TimeoutException)e ||
                    cast(NetworkException)e))
                throw new OdoodDownloadException(
                    "Cannot download %s because not-retriable error: %s".format(
                        url, e.toString),
                    e);

            // if it is last attempt and we got error, then throw it as is
            if (attempt == max_retries)
                throw new OdoodDownloadException(
                    "Cannot download %s because max attempts reached: %s".format(
                        url, e.toString),
                    e);

            // sleep for 1 second in case of failure
            Thread.sleep((attempt+1).seconds);
            warningf(
                "Cannot download %s because %s. Attempt %s/%s. Retrying",
                url, e.msg, attempt+1, max_retries);
            // and try again
            continue;
        }
        // Download successfully completed, break the cycle
        break;
    }
}


/** Generate random string of specified length
  *
  * Params:
  *     length = length of random string to generate.
  **/
string generateRandomString(in uint length) {
    import std.ascii: letters, digits;

    string result = "";
    immutable string symbol_pool = letters ~ digits;
    for(uint i; i<length; i++) result ~= symbol_pool[uniform(0, $)];
    return result;
}


/** Get cache dir for specified name if cache is configured.
  * This could be used to cached downloads like python or Odoo,
  * in cases when downloading of same file is frequent operation.
  *
  * Params:
  *     name = name of cache to get path for
  *
  * Returns: nullable path to specified directory inside cache dir.
  *     If cache is not enabled, the retuns Nullable!Path.init
  **/
Nullable!Path getCacheDir(in string name) {
    import std.process;
    auto cache_path = Path(environment.get("ODOOD_CACHE_DIR"));
    if (cache_path.isValid && cache_path.isAbsolute) {
        cache_path = cache_path.join(name);
        // Create path if it does not exists yet
        if (!cache_path.exists) cache_path.mkdir(true);
        return cache_path.nullable;
    }
    return Nullable!Path.init;
}

/** Get cache dir for specified name if cache is configured.
  * This could be used to cached downloads like python or Odoo,
  * in cases when downloading of same file is frequent operation.
  *
  * Params:
  *     name = name of cache to get path for
  *     defaultDir = default path to be returned if cache was not enabled
  *
  * Returns: path to directory inside cache dir, or default directory
  **/
Path getCacheDir(in string name, in Path defaultDir) {
    auto cache_dir = getCacheDir(name);
    if (cache_dir.isNull) return defaultDir;
    return cache_dir.get;
}
