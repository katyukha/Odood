/// Module for parsing odoo_requirements.txt files used by odoo-helper-scripts
module odood.lib.odoo_requirements;

private import std.algorithm: startsWith, splitter;
private import std.string: splitLines, strip;
private import std.uni: isWhite;
private import std.format: format;

private import thepath: Path;


enum OdooRequirementsLineType {
    repo,
    odoo_apps,
}

private struct OdooRequirementsLine {
    OdooRequirementsLineType type;
    string repo_url;
    string branch;
    string addon;
}

/** Parse odoo_requirements.txt used by odoo-helper-scripts and
  * return array of parsed lines.
  **/
OdooRequirementsLine[] parseOdooRequirements(in string content) {
    OdooRequirementsLine[] res;
    foreach(line; content.splitLines) {
        if (line.strip.startsWith("#"))
            // It is a comment. Skip
            continue;

        bool is_parsed = false;
        OdooRequirementsLine rline;
        auto args = line.strip().splitter!isWhite;
        while (!args.empty) {
            string arg = args.front;

            // If we reach comment, then we have to stop parsing this line
            if (arg.startsWith("#"))
                break;

            // Remove first param from array
            args.popFront;

            switch (arg) {
                case "--repo":
                    rline.type = OdooRequirementsLineType.repo;
                    rline.repo_url = args.front;
                    args.popFront;
                    is_parsed = true;
                    break;
                case "--github":
                    rline.type = OdooRequirementsLineType.repo;
                    rline.repo_url = "https://github.com/%s".format(args.front);
                    args.popFront;
                    is_parsed = true;
                    break;
                case "--oca":
                    rline.type = OdooRequirementsLineType.repo;
                    rline.repo_url = "https://github.com/OCA/%s".format(args.front);
                    args.popFront;
                    is_parsed = true;
                    break;
                case "-b", "--branch":
                    rline.branch = args.front;
                    args.popFront;
                    break;
                case "-m", "--module":
                    rline.addon = args.front;
                    args.popFront;
                    break;
                case "--odoo-apps":
                    rline.type = OdooRequirementsLineType.odoo_apps;
                    rline.addon = args.front;
                    args.popFront;
                    is_parsed = true;
                    break;
                default:
                    // Skip all other arguments
                    break;
            }
        }

        if (is_parsed)
            // If line was parsed sucessfully, then we could add it to result
            res ~= rline;
    }
    return res;
}

/// ditto
OdooRequirementsLine[] parseOdooRequirements(in Path path) {
    return parseOdooRequirements(path.readFileText());
}

///
unittest {
    import unit_threaded.assertions;

    auto res = parseOdooRequirements("
# Some comment
--github crnd-inc/crnd-web.git
   # Some other comment for line with incorret ident
    --repo https://github.com/crnd-inc/generic-addons.git

--odoo-apps generic_request # Some comment
");

    res.length.shouldEqual(3);

    with (res[0]) {
        type.shouldEqual(OdooRequirementsLineType.repo);
        repo_url.shouldEqual("https://github.com/crnd-inc/crnd-web.git");
        branch.shouldBeNull;
        addon.shouldBeNull;
    }

    with (res[1]) {
        type.shouldEqual(OdooRequirementsLineType.repo);
        repo_url.shouldEqual("https://github.com/crnd-inc/generic-addons.git");
        branch.shouldBeNull;
        addon.shouldBeNull;
    }

    with (res[2]) {
        type.shouldEqual(OdooRequirementsLineType.odoo_apps);
        repo_url.shouldBeNull;
        branch.shouldBeNull;
        addon.shouldEqual("generic_request");
    }
}
