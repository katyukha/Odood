/** Environment files: `NAME=value` lines, read by systemd
  * (`EnvironmentFile=`), by a shell that sources them, and by odood.
  *
  * Only the forms all three read the same way are accepted, so one file
  * gives a service and odood the same variables:
  *
  * - blank lines, and lines starting with `#`;
  * - `NAME=value`: NAME is a shell variable name, no spaces around `=`;
  * - an unquoted value made of letters, digits and `_ . / : , @ % + = -`;
  * - a single-quoted value on one line, with no `'` inside: `NAME='a b'`.
  *   Taken literally: no escapes, no `$` expansion.
  *
  * Everything else is refused with its line number: double quotes,
  * backslashes and `$` (a shell expands or unescapes them, systemd does
  * not), spaces in an unquoted value (a shell ends the value there),
  * `export` and lines without `=` (a shell runs them as commands).
  **/
module odood.lib.env_file;

private import std.array: split;
private import std.ascii: isAlpha, isAlphaNum;
private import std.exception: enforce;
private import std.format: format;
private import std.string: indexOf, stripLeft, stripRight;

private import odood.exception: OdoodException;


/** Parse environment file content. `source` names the file in errors.
  *
  * Throws: `OdoodException` on a line outside the accepted forms.
  **/
string[string] parseEnvFile(in string content, in string source) {
    string[string] res;
    // Split on '\n' only, as systemd and a shell do: a '\r' stays in the
    // line and is refused, instead of being dropped by odood alone.
    foreach(i, raw; content.split('\n')) {
        immutable line = raw.stripLeft(" \t").stripRight(" \t");
        if (line.length == 0 || line[0] == '#')
            continue;

        string error(in string problem) {
            return "%s:%s: %s".format(source, i + 1, problem);
        }

        immutable eq = line.indexOf('=');
        enforce!OdoodException(eq > 0, error("expected NAME=value"));
        immutable name = line[0 .. eq];
        enforce!OdoodException(
            isValidEnvName(name),
            error("'%s' is not a valid variable name".format(name)));

        immutable value = line[eq + 1 .. $];
        if (value.length > 0 && value[0] == '\'') {
            immutable close = value.indexOf('\'', 1);
            enforce!OdoodException(close > 0, error("unterminated single quote"));
            enforce!OdoodException(
                close == value.length - 1,
                error("unexpected text after the closing quote"));
            res[name] = value[1 .. close];
        } else {
            foreach(char c; value)
                enforce!OdoodException(
                    isUnquotedChar(c),
                    error(
                        "a value with characters other than letters, digits " ~
                        "and _ . / : , @ % + = - must be in single quotes"));
            res[name] = value;
        }
    }
    return res;
}

private bool isValidEnvName(in string name) pure nothrow @safe @nogc {
    if (name.length == 0 || !(name[0].isAlpha || name[0] == '_'))
        return false;
    foreach(char c; name)
        if (!(c.isAlphaNum || c == '_'))
            return false;
    return true;
}

private bool isUnquotedChar(in char c) pure nothrow @safe @nogc {
    if (c.isAlphaNum)
        return true;
    foreach(char p; "_./:,@%+=-")
        if (c == p)
            return true;
    return false;
}

///
unittest {
    import unit_threaded.assertions;

    parseEnvFile(
        "# CA bundle\n" ~
        "\n" ~
        "  REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt  \n" ~
        "URL=https://user@host:8443/a,b%2F+c=d-e_f.g\n" ~
        "QUOTED='$HOME \"q\" \\ # x'\n" ~
        "EMPTY=\n" ~
        "EMPTY_QUOTED=''\n" ~
        "REPEATED=a\n" ~
        "REPEATED=b\n",
        "odoo.env"
    ).shouldEqual([
        "REQUESTS_CA_BUNDLE": "/etc/ssl/certs/ca-certificates.crt",
        "URL": "https://user@host:8443/a,b%2F+c=d-e_f.g",
        "QUOTED": "$HOME \"q\" \\ # x",
        "EMPTY": "",
        "EMPTY_QUOTED": "",
        "REPEATED": "b",
    ]);
    parseEnvFile("", "odoo.env").length.shouldEqual(0);
}

/// Lines outside the accepted forms are refused with their line number
unittest {
    import unit_threaded.assertions;

    void shouldRefuse(in string line, in string message) {
        parseEnvFile("# ok\n" ~ line ~ "\n", "odoo.env")
            .shouldThrowWithMessage!OdoodException("odoo.env:2: " ~ message);
    }

    enum unquoted = "a value with characters other than letters, digits " ~
        "and _ . / : , @ % + = - must be in single quotes";
    shouldRefuse("A=\"x\"", unquoted);
    shouldRefuse("A=$HOME", unquoted);
    shouldRefuse("A=a b", unquoted);
    shouldRefuse("A= b", unquoted);
    shouldRefuse("A=~/x", unquoted);
    shouldRefuse("A=x\\", unquoted);
    shouldRefuse("A=x\r", unquoted);
    shouldRefuse("A='x", "unterminated single quote");
    shouldRefuse("A='x'y", "unexpected text after the closing quote");
    shouldRefuse("A='x' # note", "unexpected text after the closing quote");
    shouldRefuse("some-command", "expected NAME=value");
    shouldRefuse("=x", "expected NAME=value");
    shouldRefuse("export A=x", "'export A' is not a valid variable name");
    shouldRefuse("A =x", "'A ' is not a valid variable name");
    shouldRefuse("1A=x", "'1A' is not a valid variable name");
}

/// A shell sourcing the file gets the values odood parses
unittest {
    import unit_threaded.assertions;
    import thepath.utils: createTempPath;
    import theprocess: Process;

    auto root = createTempPath;
    scope(exit) root.remove();

    enum content =
        "# comment\n" ~
        "ODOOD_T_PLAIN=/etc/ssl/certs/ca-certificates.crt\n" ~
        "ODOOD_T_CHARS=_./:,@%+=-aZ9\n" ~
        "ODOOD_T_QUOTED='$HOME `id` \"q\" \\n # ; x'\n" ~
        "ODOOD_T_EMPTY=\n";
    immutable names = [
        "ODOOD_T_PLAIN", "ODOOD_T_CHARS", "ODOOD_T_QUOTED", "ODOOD_T_EMPTY"];
    auto path = root.join("odoo.env");
    path.writeFile(content);

    auto parsed = parseEnvFile(content, path.toString);
    string expected;
    foreach(name; names)
        expected ~= parsed[name] ~ "\0";

    Process("bash")
        .withArgs(
            "-c",
            `set -a; . "$1"; shift; for n in "$@"; do printf '%s\0' "${!n}"; done`,
            "bash", path.toString)
        .withArgs(names)
        .execute
        .ensureOk(true)
        .output.shouldEqual(expected);
}
