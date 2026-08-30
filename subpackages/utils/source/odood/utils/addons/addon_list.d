module odood.utils.addons.addon_list;

/** Render a set of addons as a table (Markdown / CSV), for generated addon
  * lists (e.g. an assembly's `ADDONS.md` / `ADDONS.csv`) and for CLI export.
  * Project-free: works from `OdooAddon` + its manifest only.
  **/

private import std.algorithm: sort, map;
private import std.array: array, join, appender;
private import std.string: replace, splitLines;
private import std.conv: to;
private import std.format: format;

private import odood.exception: OdoodException;
private import odood.utils.addons.addon: OdooAddon;


/// Default columns for generated addon lists (odoo-packager parity).
enum string[] DEFAULT_ADDONS_LIST_COLUMNS = [
    "system_name", "name", "license", "version", "installable", "summary", "price"];


/// Human-readable header label for an addon-list column key.
private string columnHeader(in string column) {
    switch(column) {
        case "system_name":  return "System Name";
        case "name":         return "Name";
        case "license":      return "License";
        case "version":      return "Version";
        case "installable":  return "Installable";
        case "summary":      return "Summary";
        case "price":        return "Price";
        case "author":              return "Author";
        case "website":             return "Website";
        case "category":            return "Category";
        case "maintainer":          return "Maintainer";
        case "application":         return "Application";
        case "auto_install":        return "Auto Install";
        case "tags":                return "Tags";
        case "dependencies":        return "Dependencies";
        case "python_dependencies": return "Python Dependencies";
        case "bin_dependencies":    return "Bin Dependencies";
        default:
            throw new OdoodException("Unknown addon-list column '%s'".format(column));
    }
}

/** Cell value for an addon-list column key.
  *
  * Every value is newline-flattened: a cell has to stay on a single line,
  * and any manifest field may contain line breaks, not only the obviously
  * free-form ones.
  **/
private string columnValue(in OdooAddon addon, in string column) {
    return flattenCell(columnRawValue(addon, column));
}

/// Replace line breaks in a cell value with spaces.
private string flattenCell(in string s) =>
    s.replace("\r\n", " ").replace("\n", " ").replace("\r", " ");

/// ditto columnValue, before flattening.
private string columnRawValue(in OdooAddon addon, in string column) {
    switch(column) {
        case "system_name":  return addon.name;
        case "name":         return addon.manifest.name;
        case "license":      return addon.manifest.license;
        case "version":      return addon.manifest.module_version.rawVersion;
        case "installable":  return addon.manifest.installable.to!string;
        case "summary":      return addon.manifest.summary;
        case "price":        return addon.manifest.price.is_set ? addon.manifest.price.toString : "";
        case "author":              return addon.manifest.author;
        case "website":             return addon.manifest.website;
        case "category":            return addon.manifest.category;
        case "maintainer":          return addon.manifest.maintainer;
        case "application":         return addon.manifest.application.to!string;
        case "auto_install":        return addon.manifest.auto_install.to!string;
        case "tags":                return addon.manifest.tags.join(", ");
        case "dependencies":        return addon.manifest.dependencies.join(", ");
        case "python_dependencies": return addon.manifest.python_dependencies.join(", ");
        case "bin_dependencies":    return addon.manifest.bin_dependencies.join(", ");
        default:
            throw new OdoodException("Unknown addon-list column '%s'".format(column));
    }
}

/** Build a table (header row + one row per addon) for the given column keys.
  * Addons are sorted by system name. Columns default to
  * DEFAULT_ADDONS_LIST_COLUMNS.
  **/
string[][] addonListRows(
        OdooAddon[] addons,
        in string[] columns = DEFAULT_ADDONS_LIST_COLUMNS) {
    string[][] rows;
    rows ~= columns.map!(c => columnHeader(c)).array;
    foreach(addon; addons.dup.sort!((a, b) => a.name < b.name))
        rows ~= columns.map!(c => columnValue(addon, c)).array;
    return rows;
}

/// Render a header+rows table as a GitHub-flavored Markdown table.
string renderMarkdownTable(in string[][] table) {
    if (table.length == 0)
        return "";
    string cell(in string s) => flattenCell(s).replace("|", "\\|");
    auto app = appender!string;
    app ~= "| " ~ table[0].map!(c => cell(c)).join(" | ") ~ " |\n";
    app ~= "|" ~ table[0].map!(_ => "---").join("|") ~ "|\n";
    foreach(row; table[1 .. $])
        app ~= "| " ~ row.map!(c => cell(c)).join(" | ") ~ " |\n";
    return app.data;
}

/** Neutralize a value that a spreadsheet would treat as a formula.
  *
  * Addon manifests come from third-party repositories, thus any text in
  * them is untrusted input. A cell starting with `=`, `+`, `-`, `@`, tab or
  * carriage return is evaluated as a formula by Excel and LibreOffice when
  * the file is opened (for example `=HYPERLINK("http://evil", "Click")`),
  * and quoting the field does not prevent it. Prefixing with a single quote
  * makes the spreadsheet treat the value as text.
  **/
private string csvGuardFormula(in string s) {
    import std.algorithm: canFind;
    if (s.length > 0 && "=+-@\t\r".canFind(s[0]))
        return "'" ~ s;
    return s;
}

/** Render a header+rows table as CSV.
  *
  * Every field is quoted and embedded quotes are doubled (RFC 4180), line
  * breaks are flattened, and formula-like values are neutralized.
  **/
string renderCsv(in string[][] table) {
    string cell(in string s) =>
        `"` ~ csvGuardFormula(flattenCell(s)).replace(`"`, `""`) ~ `"`;
    auto app = appender!string;
    foreach(row; table)
        app ~= row.map!(c => cell(c)).join(",") ~ "\n";
    return app.data;
}


unittest {
    import unit_threaded.assertions;
    import std.algorithm: canFind;
    import thepath: createTempPath;
    import odood.utils.addons.addon: findAddons;

    auto root = createTempPath;
    scope(exit) root.remove();

    void mkAddon(in string dir, in string manifest) {
        root.join(dir).mkdir(true);
        root.join(dir, "__manifest__.py").writeFile(manifest);
    }
    // Deliberately out of alphabetical order to check sorting.
    mkAddon("b_addon",
        `{"name": "B Addon", "version": "17.0.1.0.0", "license": "LGPL-3", ` ~
        `"summary": "Second\naddon", "installable": True}`);
    mkAddon("a_addon",
        `{"name": "A Addon", "version": "17.0.2.0.0", "license": "OPL-1", ` ~
        `"summary": "First", "installable": False, "price": 10, "currency": "USD", ` ~
        `"website": "https://example.com", "depends": ["base", "web"]}`);

    auto rows = addonListRows(findAddons(root).array);

    rows[0].should == [
        "System Name", "Name", "License", "Version", "Installable", "Summary", "Price"];
    // sorted by system name: a_addon first
    rows[1][0].should == "a_addon";
    rows[1][1].should == "A Addon";
    rows[1][4].should == "false";       // installable
    rows[1][6].should == "10 USD";      // price
    rows[2][0].should == "b_addon";
    rows[2][3].should == "17.0.1.0.0";  // version (rawVersion)
    rows[2][4].should == "true";
    rows[2][5].should == "Second addon";  // newline flattened
    rows[2][6].should == "";             // no price

    auto md = renderMarkdownTable(rows);
    md.canFind("| System Name | Name | License | Version | Installable | Summary | Price |").shouldBeTrue;
    md.canFind("|---|---|---|---|---|---|---|").shouldBeTrue;
    md.canFind("| a_addon | A Addon |").shouldBeTrue;

    auto csv = renderCsv(rows);
    csv.canFind(`"System Name","Name","License","Version","Installable","Summary","Price"`).shouldBeTrue;
    csv.canFind(`"a_addon","A Addon","OPL-1","17.0.2.0.0","false","First","10 USD"`).shouldBeTrue;

    // Custom column subset/order.
    auto rows2 = addonListRows(findAddons(root).array, ["name", "version"]);
    rows2[0].should == ["Name", "Version"];
    rows2[1].should == ["A Addon", "17.0.2.0.0"];

    // website + dependencies columns (joined; empty when absent).
    auto rows3 = addonListRows(
        findAddons(root).array, ["system_name", "website", "dependencies"]);
    rows3[0].should == ["System Name", "Website", "Dependencies"];
    rows3[1].should == ["a_addon", "https://example.com", "base, web"];
    rows3[2].should == ["b_addon", "", ""];
}


/// Untrusted manifest text must not break out of a cell, nor become a formula.
unittest {
    import unit_threaded.assertions;
    import std.algorithm: canFind;
    import thepath: createTempPath;
    import odood.utils.addons.addon: findAddons;

    auto root = createTempPath;
    scope(exit) root.remove();

    /* A manifest from a third-party repository, with:
     *  - a formula in a text field,
     *  - CR and CRLF line breaks in fields that are not free-form text.
     */
    root.join("evil_addon").mkdir(true);
    root.join("evil_addon", "__manifest__.py").writeFile(
        `{"name": "Evil", "version": "17.0.1.0.0", ` ~
        `"summary": "=HYPERLINK(\"http://evil\", \"Click\")", ` ~
        `"license": "LGPL-3\r\nInjected", "website": "https://e.com\rInjected", ` ~
        `"installable": True}`);

    auto rows = addonListRows(
        findAddons(root).array,
        ["system_name", "summary", "license", "website"]);

    // Every column is flattened, not only the free-form ones.
    rows[1][2].should == "LGPL-3 Injected";
    rows[1][3].should == "https://e.com Injected";

    auto csv = renderCsv(rows);
    // One header line + one data line: nothing broke the row apart.
    csv.splitLines.length.should == 2;
    // The formula is neutralized, and quotes are still doubled.
    csv.canFind(`"'=HYPERLINK(""http://evil"", ""Click"")"`).shouldBeTrue;
    csv.canFind("\n=").shouldBeFalse;

    // Markdown keeps one row per addon too.
    renderMarkdownTable(rows).splitLines.length.should == 3;  // header, ---, data
}
