module odood.utils;

/** This package contains various utilities that do not depend on Odoo project.
  * Thus, they could be used in other projects that do not use Odood projects.
  **/

private import core.time: Duration, seconds;
private import core.thread: Thread;
private import std.logger: warningf;
private import std.exception: enforce, basicExceptionCtors;
private import std.format: format;
private import std.random: uniform;
private import std.typecons: Nullable, nullable;
private import std.string: strip, startsWith, chompPrefix;

private import thepath: Path;
private import theprocess: Process;
private import versioned: Version;

private import odood.exception: OdoodException;


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
        .output.strip;

    enforce!OdoodException(
        python_version_raw.startsWith("Python "),
        "Cannot parse python interpreter (%s) version '%s'".format(
            interpreter_path, python_version_raw));
    return Version(python_version_raw.chompPrefix("Python "));
}


/** This exeption will be raised when it is not possible to download the file
  **/
class OdoodDownloadException : OdoodException
{
    mixin basicExceptionCtors;
}


/// A download attempt failed in a way that repeating it may fix.
private class DownloadRetryException : Exception
{
    mixin basicExceptionCtors;
}


/** Download the file from the web
  *
  * The file is written to `<dest_path>.part` and renamed to `dest_path` once
  * complete, so `dest_path` never holds a partial download or an error page:
  * callers reuse a cached download just because it exists.
  *
  * Params:
  *     url = the url to download file from
  *     dest_path = the destination path to download file to
  *     timeout = optional timeout. Default is 20 seconds.
  *     max_retries = optional max number of retries on network errors,
  *         HTTP 408, 429 and 5xx, and a connection closed before
  *         `Content-Length` bytes arrived.
  **/
void download(
        in string url,
        in Path dest_path,
        in Duration timeout=20.seconds,
        in ubyte max_retries=7) {
    import requests: Request, Response, RequestException;
    import requests.streams: ConnectError, TimeoutException, NetworkException;

    enforce!OdoodDownloadException(
        !dest_path.exists,
        "Cannot download %s to %s! Destination path already exists!".format(
            url, dest_path));

    auto part_path = Path(dest_path.toString ~ ".part");
    scope(failure) if (part_path.exists) part_path.remove();

    for(ubyte attempt = 0; attempt <= max_retries; ++attempt) {
        try {
            auto request = Request();
            request.useStreaming = true;
            request.timeout = timeout;

            auto response = request.get(url);
            if (response.code < 200 || response.code >= 300) {
                if (response.code == 408 || response.code == 429 || response.code >= 500)
                    throw new DownloadRetryException("HTTP %s".format(response.code));
                throw new OdoodDownloadException(
                    "Cannot download %s: HTTP %s".format(url, response.code));
            }
            auto stream = response.receiveAsRange();

            auto f_dest = part_path.openFile("wb");
            scope(exit) f_dest.close();

            ulong written = 0;
            while (!stream.empty) {
                f_dest.rawWrite(stream.front);
                written += stream.front.length;
                stream.popFront;
            }

            // The stream also ends, without an error, when the server closes
            // the connection early. Counted here, as `contentReceived` of
            // requests misses bytes in streaming mode. Content-Length counts
            // the bytes as sent, so it cannot be checked when requests has
            // decoded a Content-Encoding.
            if (response.contentLength >= 0 &&
                    "content-encoding" !in response.responseHeaders &&
                    written < response.contentLength)
                throw new DownloadRetryException(
                    "connection closed after %s of %s bytes".format(
                        written, response.contentLength));
        } catch (OdoodDownloadException e) {
            // Refused by the server: final, and its message says why.
            throw e;
        } catch (Exception e) {
            // If exception is not retriable, just reraise it.
            if (!(cast(RequestException)e ||
                    cast(ConnectError)e ||
                    cast(TimeoutException)e ||
                    cast(NetworkException)e ||
                    cast(DownloadRetryException)e))
                throw new OdoodDownloadException(
                    "Cannot download %s because not-retriable error: %s".format(
                        url, e.toString),
                    e);

            // if it is last attempt and we got error, then throw it as is
            if (attempt == max_retries)
                throw new OdoodDownloadException(
                    "Cannot download %s because max (%s) attempts reached: %s".format(
                        url, attempt, e.toString),
                    e);

            // sleep for some time in case of failure
            Thread.sleep((attempt + uniform(1, 5)).seconds);
            warningf(
                "Cannot download %s because %s. Attempt %s/%s. Retrying",
                url, e.msg, attempt+1, max_retries);
            // and try again
            continue;
        }
        // Download successfully completed, break the cycle
        break;
    }
    part_path.rename(dest_path);
}

// Only failures that may pass are retried, and none leaves a file behind.
unittest {
    import core.thread: Thread;
    import core.time: msecs;
    import std.algorithm: canFind;
    import std.array: replicate;
    import std.socket: InternetAddress, Socket, SocketSet, SocketShutdown, TcpSocket;
    import std.string: indexOf;
    import thepath.utils: createTempPath;
    import unit_threaded.assertions;

    // Serve the raw HTTP `responses` on a local port, one per connection.
    Thread serve(in string[] responses, out ushort port) {
        auto listener = new TcpSocket();
        listener.bind(new InternetAddress("127.0.0.1", 0));
        listener.listen(1);
        port = (cast(InternetAddress) listener.localAddress).port;
        auto thread = new Thread({
            scope(exit) listener.close();
            foreach(response; responses) {
                // Gives up on the rest when the client stops connecting.
                auto ready = new SocketSet();
                ready.add(listener);
                if (Socket.select(ready, null, null, 5.seconds) <= 0)
                    return;
                auto conn = listener.accept();
                scope(exit) conn.close();
                // Read the request first: closing with unread data resets the
                // connection, and the client may lose the response.
                char[] request;
                char[1024] buffer;
                while (!request.canFind("\r\n\r\n")) {
                    auto received = conn.receive(buffer[]);
                    if (received <= 0)
                        break;
                    request ~= buffer[0 .. received];
                }
                // The headers alone first, as they often arrive: requests
                // then leaves the next read out of `contentReceived` when the
                // body takes several.
                immutable head = response.indexOf("\r\n\r\n") + 4;
                conn.send(response[0 .. head]);
                Thread.sleep(50.msecs);
                conn.send(response[head .. $]);
                conn.shutdown(SocketShutdown.BOTH);
            }
        });
        thread.start();
        return thread;
    }

    string respond(in string status, in string content, in size_t length) {
        return "HTTP/1.1 %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s".format(
            status, length, content);
    }

    auto root = createTempPath;
    scope(exit) root.remove();
    ushort port;

    // A client error fails at once.
    auto server = serve([respond("404 Not Found", "Not Found", 9)], port);
    auto missing = download(
            "http://127.0.0.1:%s/odoo.tar.gz".format(port),
            root.join("missing.tar.gz"),
            max_retries: 1)
        .shouldThrow!OdoodDownloadException;
    server.join();
    missing.msg.shouldEqual(
        "Cannot download http://127.0.0.1:%s/odoo.tar.gz: HTTP 404".format(port));
    root.join("missing.tar.gz").exists.shouldBeFalse;
    root.join("missing.tar.gz.part").exists.shouldBeFalse;

    // A server error is retried. The body takes several reads of requests.
    immutable archive = "archive".replicate(10_000);
    server = serve([
        respond("503 Service Unavailable", "Busy", 4),
        respond("200 OK", archive, archive.length),
    ], port);
    download(
        "http://127.0.0.1:%s/odoo.tar.gz".format(port),
        root.join("busy.tar.gz"),
        max_retries: 1);
    server.join();
    root.join("busy.tar.gz").readFileText.shouldEqual(archive);
    root.join("busy.tar.gz.part").exists.shouldBeFalse;

    // A connection closed before Content-Length bytes is a failure too.
    server = serve([respond("200 OK", "arch", 7)], port);
    auto cut = download(
            "http://127.0.0.1:%s/odoo.tar.gz".format(port),
            root.join("cut.tar.gz"),
            max_retries: 0)
        .shouldThrow!OdoodDownloadException;
    server.join();
    cut.msg.canFind("connection closed after 4 of 7 bytes").shouldBeTrue;
    root.join("cut.tar.gz").exists.shouldBeFalse;
    root.join("cut.tar.gz.part").exists.shouldBeFalse;
}


/** Get a free TCP port by binding to port 0 and letting the OS assign one.
  *
  * Returns: a free port number.
  * Throws: OdoodException if unable to obtain a free port.
  **/
ushort getFreePort() {
    import std.socket: TcpSocket, InternetAddress, SocketOSException;

    TcpSocket sock;
    try {
        sock = new TcpSocket();
        scope(exit) sock.close();
        sock.bind(new InternetAddress("127.0.0.1", 0));
        return (cast(InternetAddress) sock.localAddress).port;
    } catch (SocketOSException e) {
        throw new OdoodException("Cannot obtain a free port: " ~ e.msg);
    }
}

// Test getFreePort
unittest {
    import std.socket: TcpSocket, InternetAddress, SocketOSException;
    import unit_threaded.assertions;

    // Should return a valid port
    auto port = getFreePort();
    assert(port > 0);

    // Should return different ports on subsequent calls (not guaranteed, but very likely)
    auto port2 = getFreePort();
    // Both should be valid
    assert(port2 > 0);

    // Verify the port is actually free by binding to it
    auto sock = new TcpSocket();
    scope(exit) sock.close();
    // Should not throw
    sock.bind(new InternetAddress("127.0.0.1", port));
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


// Test getCacheDir
unittest {
    import std.process;
    import thepath.utils: createTempPath;
    import unit_threaded.assertions;

    auto save_env = environment.toAA;
    scope(exit) {
        // Restore env on exit
        if ("ODOOD_CACHE_DIR" in save_env)
            environment["ODOOD_CACHE_DIR"] = save_env["ODOOD_CACHE_DIR"];
        else
            environment.remove("ODOOD_CACHE_DIR");
    }

    // No cachedir defined in env
    if ("ODOOD_CACHE_DIR" in environment)
        environment.remove("ODOOD_CACHE_DIR");

    getCacheDir("cache-42").isNull.shouldBeTrue;

    environment["ODOOD_CACHE_DIR"] = "some-invalid:path~here";

    getCacheDir("cache-42").isNull.shouldBeTrue;

    auto root = createTempPath;
    scope(exit) root.remove();

    environment["ODOOD_CACHE_DIR"] = root.join("cache-root").toString;
    getCacheDir("cache-42").isNull.shouldBeFalse;
    getCacheDir("cache-42").get.shouldEqual(root.join("cache-root", "cache-42"));
    getCacheDir("cache-42").get.isAbsolute.shouldBeTrue;
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

// Test getCacheDir
unittest {
    import std.process;
    import thepath.utils: createTempPath;
    import unit_threaded.assertions;

    auto save_env = environment.toAA;
    scope(exit) {
        // Restore env on exit
        if ("ODOOD_CACHE_DIR" in save_env)
            environment["ODOOD_CACHE_DIR"] = save_env["ODOOD_CACHE_DIR"];
        else
            environment.remove("ODOOD_CACHE_DIR");
    }

    auto root = createTempPath;
    scope(exit) root.remove();

    // No cachedir defined in env
    if ("ODOOD_CACHE_DIR" in environment)
        environment.remove("ODOOD_CACHE_DIR");

    getCacheDir("cache-42", root.join("default")).shouldEqual(root.join("default"));
    getCacheDir("cache-42", root.join("default")).isAbsolute.shouldBeTrue;

    // Set cachedir to invalid path
    environment["ODOOD_CACHE_DIR"] = "some-invalid:path~here";

    getCacheDir("cache-42", root.join("default")).shouldEqual(root.join("default"));
    getCacheDir("cache-42", root.join("default")).isAbsolute.shouldBeTrue;

    // Set cachedir to valid path
    environment["ODOOD_CACHE_DIR"] = root.join("cache-root").toString;
    getCacheDir("cache-42", root.join("default")).shouldEqual(root.join("cache-root", "cache-42"));
    getCacheDir("cache-42", root.join("default")).isAbsolute.shouldBeTrue;
}
