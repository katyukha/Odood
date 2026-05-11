module odood.lib.addons.changes;

private import std.algorithm: canFind;

private import versioned: Version, VersionPart;

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
    OdooAddonChangelogEntry[] changelog;
}


/** Tracks addon-level changes between two states (assembly versions, repo releases, etc.)
  * and computes the appropriate version bump for the containing artifact.
  *
  * Includes:
  * - Added addons
  * - Removed addons
  * - Updated addons
  **/
class AddonRepositoryChanges {
    OdooStdVersion repo_version;
    AddonAdded[] addons_added;
    string[] addons_removed;
    AddonUpdated[] addons_updated;
    NotableChanges[] notable_changes;

    this(in OdooStdVersion repo_version) {
        this.repo_version = repo_version;
    }

    /** Add info about addon removed
      **/
    void logAddonRemoved(in string name) {
        addons_removed ~= name;
    }

    /** Add info about addon added
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
            in OdooAddonChangelogEntry[] changelog) {
        addons_updated ~= AddonUpdated(name, old_version, new_version);
        if (changelog.length > 0)
            notable_changes ~= NotableChanges(name, old_version, new_version, changelog.dup);
    }

    /** Compute and apply the version bump based on recorded changes.
      *
      * Rules:
      * - Any added or removed addon → MAJOR bump.
      * - Otherwise, take the minimum VersionPart across all updated addons
      *   (MAJOR=0 < MINOR=1 < PATCH=2), i.e. the highest-severity change wins.
      * - Addons with non-standard versions count as MINOR.
      * - No changes → version unchanged.
      **/
    void postProcess() {
        if (addons_added.length > 0 || addons_removed.length > 0)
            repo_version = repo_version.incMajor;
        else if (addons_updated.length > 0) {
            auto vpart = VersionPart.PATCH;
            foreach(addon; addons_updated) {
                if ((!addon.old_version.isStandard() || !addon.new_version.isStandard()) && vpart > VersionPart.MINOR) {
                    vpart = VersionPart.MINOR;
                    continue;
                }
                if (addon.old_version == addon.new_version)
                    continue;

                auto diff = addon.old_version.differAt(addon.new_version);
                if (diff < vpart)
                    vpart = diff;
                if (vpart == VersionPart.MAJOR)
                    break;
            }
            repo_version = repo_version.incVersion(vpart);
        }
    }
}
