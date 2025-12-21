module odood.lib.assembly.changes;

private import std.algorithm: canFind;

private import versioned: Version;

private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.addons.addon;
private import odood.utils.addons.addon_changelog;


struct AddonAdded {
    string name;
    OdooStdVersion new_version;
}

struct AddonUpdated {
    string name;
    OdooStdVersion old_version;
    OdooStdVersion new_version;
}

struct NotableChanges {
    string name;
    OdooStdVersion old_version;
    OdooStdVersion new_version;
    OdooAddonChangelogEntrie[] changelog;
}


/** AssemblyChanges - struct that handles changes related to assembly.
  * Includes:
  * - Added addons
  * - Removed addons
  * - Updated addons
  **/
class AssemblyChanges {
    AddonAdded[] addons_added;
    string[] addons_removed;
    AddonUpdated[] addons_updated;
    NotableChanges[] notable_changes;

    /** Add info about addon removed from assembly
      **/
    void logAddonRemoved(in string name) {
        addons_removed ~= name;
    }

    /** Add info about addon added to assembly
      **/
    void logAddonAdded(in string name, in OdooStdVersion addon_version) {
        addons_added ~= AddonAdded(name, addon_version);
    }

    /** Add info about addon updated
      **/
    void logAddonUpdated(
            in string name,
            in OdooStdVersion old_version,
            in OdooStdVersion new_version,
            in OdooAddonChangelogEntrie[] changelog) {
        addons_updated ~= AddonUpdated(name, old_version, new_version);
        if (changelog.length > 0)
            notable_changes ~= NotableChanges(name, old_version, new_version, changelog.dup);
    }
}

