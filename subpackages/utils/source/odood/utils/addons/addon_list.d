module odood.utils.addons.addon_list;

/** Render a set of addons as a table (Markdown / CSV), for generated addon
  * lists (e.g. an assembly's `ADDONS.md` / `ADDONS.csv`) and for CLI export.
  * Project-free: works from `OdooAddon` + its manifest only.
  **/

private import std.algorithm: sort, map;
private import std.array: array, join, appender;
private import std.string: replace;
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

/// Cell value for an addon-list column key. Text fields are newline-flattened.
private string columnValue(in OdooAddon addon, in string column) {
    string flatten(in string s) => s.replace("\n", " ").replace("\r", " ");
    switch(column) {
        case "system_name":  return addon.name;
        case "name":         return flatten(addon.manifest.name);
        case "license":      return addon.manifest.license;
        case "version":      return addon.manifest.module_version.rawVersion;
        case "installable":  return addon.manifest.installable.to!string;
        case "summary":      return flatten(addon.manifest.summary);
        case "price":        return addon.manifest.price.is_set ? addon.manifest.price.toString : "";
        case "author":              return flatten(addon.manifest.author);
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
    string cell(in string s) => s.replace("|", "\\|").replace("\n", " ");
    auto app = appender!string;
    app ~= "| " ~ table[0].map!(c => cell(c)).join(" | ") ~ " |\n";
    app ~= "|" ~ table[0].map!(_ => "---").join("|") ~ "|\n";
    foreach(row; table[1 .. $])
        app ~= "| " ~ row.map!(c => cell(c)).join(" | ") ~ " |\n";
    return app.data;
}

/// Render a header+rows table as CSV (every field quoted, embedded quotes doubled).
string renderCsv(in string[][] table) {
    string cell(in string s) => `"` ~ s.replace(`"`, `""`).replace("\n", " ") ~ `"`;
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
