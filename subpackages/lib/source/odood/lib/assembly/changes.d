module odood.lib.assembly.changes;

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


/** AssemblyChanges - struct that handles changes related to assembly.
  * Includes:
  * - Added addons
  * - Removed addons
  * - Updated addons
  **/
class AssemblyChanges {
    OdooStdVersion assembly_version;
    AddonAdded[] addons_added;
    string[] addons_removed;
    AddonUpdated[] addons_updated;
    NotableChanges[] notable_changes;

    this(in OdooStdVersion assembly_version) {
        this.assembly_version = assembly_version;
    }

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
            in OdooAddonChangelogEntry[] changelog) {
        addons_updated ~= AddonUpdated(name, old_version, new_version);
        if (changelog.length > 0)
            notable_changes ~= NotableChanges(name, old_version, new_version, changelog.dup);
    }

    /** Complete changes processing
      **/
    void postProcess() {
        if (addons_added.length > 0 || addons_removed.length > 0)
            assembly_version = assembly_version.incMajor;
        else if (addons_updated.length > 0) {
            // Check addon versions only if there are changed addons and
            // no addons were added or removed
            auto vpart = VersionPart.PATCH;
            foreach(addon; addons_updated) {
                if ((!addon.old_version.isStandard() || !addon.new_version.isStandard()) && vpart > VersionPart.MINOR) {
                    /* If vpart is PATCH or PRERELEASE or BUILD, that we change it to MINOR.
                     * Addon has incorect version, thus we cannot determine exactly, how we have to update repo version,
                     * but we can assume that in average that are minor changes.
                     **/
                    vpart = VersionPart.MINOR;
                    continue;
                }
                if (addon.old_version == addon.new_version)
                    // Addons did not changed version, thus we assume that it is patch update.
                    // Thus nothing to do at this step.
                    continue;

                auto diff = addon.old_version.differAt(addon.new_version);
                if (diff < vpart)
                    /* Here we update vpart to highest priority.
                     * because in `versioned` lib following is true:
                     * - VersionPart.MAJOR < VersionPart.MINOR
                     * - VersionPart.MINOR < VersionPart.PATCH
                     * Thus we can do it in this way
                     */
                    vpart = diff;
                if (vpart == VersionPart.MAJOR)
                    /* We already detect, that we need to update major part of version,
                     * thus, there is no need for further processing.
                     * Let's break the loop.
                     */
                    break;
            }
            assembly_version = assembly_version.incVersion(vpart);
        }
    }
}

