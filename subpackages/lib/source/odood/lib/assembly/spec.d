module odood.lib.assembly.spec;

private import std.typecons;
private import std.string;
private import std.exception: enforce;
private import std.algorithm;
private import std.array: array, empty;
private import std.digest.sha;

private import dyaml: Node;

private import odood.lib.assembly.exception: OdoodAssemblyException;
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

// TODO: May be move Odoo serie to spec instead of assembly

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

    // Name could be used to reffer to this 
    string name=null;
    GitURL git_url;
    string git_ref;

    /// Hash
    @property hashString() const {
        string res = git_url.toString();
        if (git_ref)
            res ~= "@" ~ git_ref;
        return sha1Of(res).toHexString();
    }

    private this(GitURL git_url, in string name=null, in string git_ref=null) {
        this.git_url = git_url;
        this.name = name;
        this.git_ref = git_ref;
    }

    private this(in Node yaml_node) {
        enforce!OdoodAssemblyException(
            yaml_node.containsKey("url"),
            "Invalid spec! Source url not specified");
        git_url = yaml_node["url"].as!string;
        if (yaml_node.containsKey("name"))
            name = yaml_node["name"].as!string;
        if (yaml_node.containsKey("ref"))
            git_ref = yaml_node["ref"].as!string;
    }

    private Node toYAML() const {
        auto result = Node(["url": git_url.toString]);
        if (!name.empty)
            result["name"] = name;
        if (!git_ref.empty)
            result["ref"] = git_ref;
        return result;
    }

    string toString() const {
        string res = "";
        if (!name.empty)
            res ~= name ~ " - ";
        res ~= git_url.toString;
        if (!git_ref.empty)
            res ~= "@" ~ git_ref;
        return res;
    }
}

struct AssemblySpec {
    private AssemblySpecAddon[] _addons;
    private AssemblySpecSource[] _sources;

    this(in Node yaml_node) {
        auto spec = yaml_node["spec"];
        foreach(node; spec["addons-list"].sequence)
            _addons ~= AssemblySpecAddon(node);

        foreach(node; spec["sources-list"].sequence)
            _sources ~= AssemblySpecSource(node);
    }

    /// Addons that have to be present in this assembly
    @property auto addons() const => _addons;

    /// Git repositories to fetch addons from
    @property auto sources() const => _sources;

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

    /// Find source by name
    Nullable!AssemblySpecSource getSource(in string name) const {
        foreach(source; _sources)
            if (source.name == name)
                return cast(Nullable!AssemblySpecSource)source.nullable;
        return Nullable!AssemblySpecSource.init;
    }

    auto toYAML() const {
        return Node([
            "spec": Node([
                "addons-list": _addons.map!((n) => n.toYAML).array,
                "sources-list": _sources.map!((s) => s.toYAML).array,
            ]),
        ]);
    }

    /* TODO:
     *     - Add spec validation
     *     - Add utils for better spec processing
     */
}
