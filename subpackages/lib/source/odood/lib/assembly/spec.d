module odood.lib.assembly.spec;

private import std.typecons;
private import std.logger;
private import std.string;
private import std.exception: enforce;
private import std.algorithm;
private import std.array: array, empty;
private import std.digest.sha;

private import dyaml: Node;

private import odood.lib.assembly.exception: OdoodAssemblyException, OdoodAssemblyInvalidSpecException;
private import odood.git.url: GitURL;
private import odood.utils.odoo.serie: OdooSerie;


/** This module provides utilities to work with assembly spec.
  * Assembly spec is YAML file, that describes what addons have to be included in assembly
  * and in what sources to search for addons.
  *
  * Assembly spec consists of following sections:
  * - addons
  * - git-sources
  *
  **/


/** Type of assembly layout.
  * - STANDARD - All addons will be placed to `dist` folder.
  * - FLAT - All addons will be placed in root folder of repo.
  **/
enum AssemblyLayout {
    STANDARD = 1,
    FLAT = 2,
}


/// Default layout
alias AssemblyDefaultLayout = AssemblyLayout.STANDARD;


/** Representation of addon in assembly specification
  *
  **/
struct AssemblySpecAddon {
    string name;
    string source_name=null;
    bool from_odoo_apps=false;

    private this(in string name, in string source_name=null, in bool from_odoo_apps=false) {
        this.name = name;
        this.source_name = source_name;
        this.from_odoo_apps = from_odoo_apps;
    }

    /** Load addon spec from yaml node
      *
      * It could be simple string or mapping
      * In case if it is simple string, then it is name of addon.
      * If it is mapping, then it must contain field 'name', that is required
      **/
    private this(in Node yaml_node) {
        if (yaml_node.nodeTypeString == "mapping") {
            enforce!OdoodAssemblyException(
                yaml_node.containsKey("name"),
                "Invalid spec! Addon name not specified.");
            name = yaml_node["name"].as!string;
            if (yaml_node.containsKey("source"))
                source_name = yaml_node["source"].as!string;
            if (yaml_node.containsKey("odoo_apps"))
                from_odoo_apps = yaml_node["odoo_apps"].as!bool;
        } else {
            name = yaml_node.as!string;
        }
    }

    private Node toYAML() const {
        auto result = Node(["name": name]);
        if (!source_name.empty)
            result["source"] = source_name;
        if (from_odoo_apps)
            result["odoo_apps"] = from_odoo_apps;
        return result;
    }

    /** Display string representation of addon
      **/
    string toString() const {
        string res = name;
        if (!source_name.empty)
            res ~= " (from '%s' repo)".format(source_name);
        else if (from_odoo_apps)
            res ~= " (from Odoo Apps)";
        return res;
    }
}

struct AssemblySpecSource {

    /// Name could be used to reffer to this
    string name=null;

    /// URL of git repository
    GitURL git_url;

    /// Reference to fetch (usually branch name)
    string git_ref;

    /// Optional commit hash to pin to after fetching ref.
    /// Requires git_ref to be set.
    string git_commit;

    /// Access group: name of access credential to apply to this repo
    /// Credentials usually provided via environment variablse
    string access_group=null;

    /// Do not search for addons in this repo, unless it is mentioned as source in addon definition.
    bool no_search=false;

    /// Hash
    @property string hashString() const {
        string res = git_url.toString();
        if (git_ref)
            res ~= "@" ~ git_ref;
        if (git_commit)
            res ~= "#" ~ git_commit;
        return sha1Of(res).toHexString().idup;
    }

    private this(GitURL git_url, in string name=null, in string git_ref=null, in string access_group=null) {
        this.git_url = git_url;
        this.name = name;
        this.git_ref = git_ref;
        this.access_group = access_group;
    }

    private this(in Node yaml_node) {
        enforce!OdoodAssemblyException(
            yaml_node.containsKey("url") || yaml_node.containsKey("github") || yaml_node.containsKey("oca") || yaml_node.containsKey("crnd"),
            "Invalid spec! Cannot determine url for git source: no 'url' nor 'github' neither 'oca' neither 'crnd' property specified.");
        if (yaml_node.containsKey("url"))
            git_url = yaml_node["url"].as!string;
        else if (yaml_node.containsKey("github"))
            git_url = "https://github.com/" ~ yaml_node["github"].as!string;
        else if (yaml_node.containsKey("oca"))
            git_url = "https://github.com/oca/" ~ yaml_node["oca"].as!string;
        else if (yaml_node.containsKey("crnd"))
            git_url = "ssh://git@gitlab.crnd.pro/" ~ yaml_node["crnd"].as!string;
        else
            // Should be unreachable, because check at the start of constructor.
            assert(0, "Invalid spec");

        if (yaml_node.containsKey("name"))
            name = yaml_node["name"].as!string;

        if (yaml_node.containsKey("ref"))
            git_ref = yaml_node["ref"].as!string;
        else if (yaml_node.containsKey("branch"))
            // CRND odoo-packager compatibility
            git_ref = yaml_node["branch"].as!string;

        if (yaml_node.containsKey("commit"))
            git_commit = yaml_node["commit"].as!string;

        if (yaml_node.containsKey("access-group"))
            access_group = yaml_node["access-group"].as!string;
        if (yaml_node.containsKey("no-search"))
            no_search = yaml_node["no-search"].as!bool;
    }

    private Node toYAML() const {
        auto result = Node(["url": git_url.toString]);
        if (!name.empty)
            result["name"] = name;
        if (!git_ref.empty)
            result["ref"] = git_ref;
        if (!git_commit.empty)
            result["commit"] = git_commit;
        if (!access_group.empty)
            result["access-group"] = access_group;

        if (no_search)
            // no_search is bool and is set to false by default,
            // thus, output it into yaml only if it is set
            result["no-search"] = no_search;
        return result;
    }

    string toString() const {
        string res = "";
        if (!name.empty)
            res ~= name ~ " - ";
        res ~= git_url.toString;
        if (!git_ref.empty)
            res ~= "@" ~ git_ref;
        if (!git_commit.empty)
            res ~= "#" ~ git_commit;
        return res;
    }
}


/** Assembly Specification representation.
  **/
struct AssemblySpec {
    private AssemblySpecAddon[] _addons;
    private AssemblySpecSource[] _sources;
    private AssemblyLayout _layout = AssemblyDefaultLayout;
    private string[] _known_addons;

    this(in Node yaml_node) {
        enforce!OdoodAssemblyInvalidSpecException(
            yaml_node.containsKey("spec"),
            "Invalid assembly spec: 'spec' key missing!");
        auto spec = yaml_node["spec"];

        enforce!OdoodAssemblyInvalidSpecException(
            spec.containsKey("addons-list"),
            "Invalid assembly spec: 'spec.addons-list' key missing!");
        foreach(node; spec["addons-list"].sequence)
            _addons ~= AssemblySpecAddon(node);

        if (spec.containsKey("sources-list"))
            foreach(node; spec["sources-list"].sequence)
                _sources ~= AssemblySpecSource(node);
        else if (spec.containsKey("git-sources"))
            foreach(node; spec["git-sources"].sequence)
                _sources ~= AssemblySpecSource(node);

        if (spec.containsKey("known-addons"))
            _known_addons = spec["known-addons"].sequence.map!(i => i.as!string).array;

        if (spec.containsKey("layout")) {
            switch (spec["layout"].as!string) {
                case "standard":
                    _layout = AssemblyLayout.STANDARD;
                    break;
                case "flat":
                    _layout = AssemblyLayout.FLAT;
                    break;
                default:
                    throw new OdoodAssemblyInvalidSpecException(
                        "Invalid layout type '%s'".format(spec["layout"].as!string)
                    );
            }
        }
    }

    /// Addons that have to be present in this assembly
    @property auto addons() const => _addons;

    /// Git repositories to fetch addons from
    @property auto sources() const => _sources;

    /// Assembly layout
    @property auto layout() const => _layout;

    /// ditto
    @property void layout(in AssemblyLayout layout) {
        _layout = layout;
    }

    /// List of known addons, that supposed to be present on destination server.
    /// These addons will be ignored during dependency validation
    @property auto known_addons() const => _known_addons;

    package(odood) void addSource(in GitURL git_url, in string name=null, in string git_ref=null) {
        foreach(source; _sources)
            if (source.git_url == git_url && source.name == name && source.git_ref == git_ref)
                // This source already exists
                return;
        _sources ~= AssemblySpecSource(git_url: git_url, name: name, git_ref: git_ref);
    }

    package(odood) void addAddon(in string name, in string source_name=null, in bool from_odoo_apps=false) {
        _addons ~= AssemblySpecAddon(name: name, source_name: source_name, from_odoo_apps: from_odoo_apps);
    }

    package(odood) void addKnownAddon(in string name) {
        _known_addons ~= name;
    }

    /// Find source by name
    Nullable!AssemblySpecSource getSource(in string name) const {
        foreach(source; _sources)
            if (source.name == name)
                return cast(Nullable!AssemblySpecSource)source.nullable;
        return Nullable!AssemblySpecSource.init;
    }

    /** Validate spec
      **/
    void validate() const {
        auto duplicated_addons = _addons.map!((a) => a.name).array.dup.sort.group.filter!((t) => t[1] > 1).array;
        enforce!OdoodAssemblyInvalidSpecException(
            duplicated_addons.length == 0,
            "There are duplicated addons:\n%s".format(
                duplicated_addons.map!((a) => "%s: %s".format(a[0], a[1])).join(",\n")));

        foreach(source; _sources)
            enforce!OdoodAssemblyInvalidSpecException(
                source.git_commit.empty || !source.git_ref.empty,
                "Source '%s': 'commit' requires 'ref' to be set".format(source.git_url));
    }

    auto toYAML() const {
        auto res = Node([
            "spec":["addons-list": _addons.map!((n) => n.toYAML).array],
        ]);
        res["spec"]["sources-list"] = _sources.map!((s) => s.toYAML).array;
        if (!_known_addons.empty)
            res["spec"]["known-addons"] = _known_addons;
        if (_layout != AssemblyDefaultLayout)
            final switch(_layout) {
                case AssemblyLayout.STANDARD:
                    res["spec"]["layout"] = "standard";
                    break;
                case AssemblyLayout.FLAT:
                    res["spec"]["layout"] = "flat";
                    break;
            }
        return res;
    }

    /* TODO:
     *     - Add utils for better spec processing
     */
}


// Test assembly spec base
unittest {
    import std.array: Appender;
    import dyaml;
    import thepath;
    import unit_threaded.assertions;

    Node yaml_spec = dyaml.Loader.fromFile(
        Path("test-data", "assemblies", "assembly1", "odood-assembly.yml").toString()
    ).load();
    auto spec = AssemblySpec(yaml_spec);
    spec.validate;  // Ensure spec is valid

    spec.sources.length.should == 2;
    spec.sources.map!((s) => s.git_url.toString).canFind("https://github.com/crnd-inc/generic-addons").shouldBeTrue;
    spec.sources.map!((s) => s.git_url.toString).canFind("https://github.com/oca/web").shouldBeTrue;

    spec.sources[0].git_url.toString.should == "https://github.com/crnd-inc/generic-addons";
    spec.sources[0].name.should == "cga";
    spec.sources[0].git_ref.should == "";
    spec.sources[0].access_group.should == "";
    spec.sources[0].no_search.should == false;

    spec.sources[1].git_url.toString.should == "https://github.com/oca/web";
    spec.sources[1].name.should == "";
    spec.sources[1].git_ref.should == "";
    spec.sources[1].access_group.should == "";
    spec.sources[1].no_search.should == false;

    spec.addons.length.should == 3;
    spec.addons.map!((s) => s.name).canFind("generic_mixin").shouldBeTrue;
    spec.addons.map!((s) => s.name).canFind("web_chatter_position").shouldBeTrue;
    spec.addons.map!((s) => s.name).canFind("kw_api_connector").shouldBeTrue;

    spec.addons[0].name.should == "generic_mixin";
    spec.addons[0].source_name.should == "cga";
    spec.addons[0].from_odoo_apps.should == false;

    spec.addons[1].name.should == "web_chatter_position";
    spec.addons[1].source_name.should == "";
    spec.addons[1].from_odoo_apps.should == false;

    spec.addons[2].name.should == "kw_api_connector";
    spec.addons[2].source_name.should == "";
    spec.addons[2].from_odoo_apps.should == true;

    spec.known_addons.should == ["my_test_addon"];

    spec.layout.should == AssemblyLayout.STANDARD;

    // Add addon to spec
    spec.addAddon("generic_condition");

    spec.addons.length.should == 4;
    spec.addons.map!((s) => s.name).should == ["generic_mixin", "web_chatter_position", "kw_api_connector", "generic_condition"];
    spec.addons[3].name.should == "generic_condition";
    spec.addons[3].source_name.should == "";
    spec.addons[3].from_odoo_apps.should == false;

    // Add source
    spec.addSource(GitURL("https://github.com/OCA/server-tools"));

    spec.sources.length.should == 3;
    spec.sources.map!((s) => s.git_url.toString).should == [
        "https://github.com/crnd-inc/generic-addons",
        "https://github.com/oca/web",
        "https://github.com/OCA/server-tools",
    ];

    // Try to add same addon second time
    spec.addSource(GitURL("https://github.com/OCA/server-tools"));

    // Ensure there is no changes.
    // TODO: May be raise error on validation instead?
    spec.sources.length.should == 3;
    spec.sources.map!((s) => s.git_url.toString).should == [
        "https://github.com/crnd-inc/generic-addons",
        "https://github.com/oca/web",
        "https://github.com/OCA/server-tools",
    ];

    // Test output
    auto stream = new Appender!string();
    auto dumper = dyaml.dumper.dumper();
    dumper.defaultCollectionStyle = dyaml.style.CollectionStyle.block;
    dumper.dump(stream, spec.toYAML);

    stream.data.should == 
"%YAML 1.1
---
spec:
  addons-list:
  - name: generic_mixin
    source: cga
  - name: web_chatter_position
  - name: kw_api_connector
    odoo_apps: true
  - name: generic_condition
  sources-list:
  - url: https://github.com/crnd-inc/generic-addons
    name: cga
  - url: https://github.com/oca/web
  - url: https://github.com/OCA/server-tools
  known-addons:
  - my_test_addon
";
}

// Load assembly with duplicated addon
unittest {
    import std.array: Appender;
    import dyaml;
    import thepath;
    import unit_threaded.assertions;

    Node yaml_spec = dyaml.Loader.fromFile(
        Path("test-data", "assemblies", "assembly2", "odood-assembly.yml").toString()
    ).load();
    auto spec = AssemblySpec(yaml_spec);

    // Spec is not valid, because it defines same addon two times
    spec.validate.shouldThrow!OdoodAssemblyInvalidSpecException;
}

// Load assembly with addons only
unittest {
    import std.array: Appender;
    import dyaml;
    import thepath;
    import unit_threaded.assertions;

    Node yaml_spec = dyaml.Loader.fromFile(
        Path("test-data", "assemblies", "assembly3", "odood-assembly.yml").toString()
    ).load();
    auto spec = AssemblySpec(yaml_spec);

    // Spec is valid
    spec.validate;

    spec.sources.length.should == 0;

    spec.addons.length.should == 2;
    spec.addons.map!((s) => s.name).canFind("generic_mixin").shouldBeTrue;
    spec.addons.map!((s) => s.name).canFind("kw_api_connector").shouldBeTrue;

    spec.addons[0].name.should == "generic_mixin";
    spec.addons[1].source_name.should == "";
    spec.addons[0].from_odoo_apps.should == true;

    spec.addons[1].name.should == "kw_api_connector";
    spec.addons[1].source_name.should == "";
    spec.addons[1].from_odoo_apps.should == true;

    spec.layout.should == AssemblyLayout.STANDARD;
}
