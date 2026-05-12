module odood.lib.addons.changes;

private import std.algorithm: canFind;

private import versioned: Version, VersionPart;
private import thepath: Path;

private import odood.utils.odoo.std_version: OdooStdVersion;
private import odood.utils.addons.addon;
private import odood.utils.addons.addon_changelog;


struct AddonAdded {
    string name;
    Path path;              /// path relative to repo root
    OdooStdVersion new_version;
}

struct AddonUpdated {
    string name;
    Path old_path;          /// path in start_ref, relative to repo root
    Path new_path;          /// path in end_ref, relative to repo root (differs on move)
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

    /** True if any addon was added, removed, or updated. **/
    @property bool has_changes() const {
        return addons_added.length > 0
            || addons_removed.length > 0
            || addons_updated.length > 0;
    }

    /** Add info about addon removed
      **/
    void logAddonRemoved(in string name) {
        addons_removed ~= name;
    }

    /** Add info about addon added
      **/
    void logAddonAdded(in string name, in Path path, in OdooStdVersion addon_version) {
        addons_added ~= AddonAdded(name, path, addon_version);
    }

    /** Add info about addon updated
      **/
    void logAddonUpdated(
            in string name,
            in Path old_path,
            in Path new_path,
            in OdooStdVersion old_version,
            in OdooStdVersion new_version,
            in OdooAddonChangelogEntry[] changelog) {
        addons_updated ~= AddonUpdated(name, old_path, new_path, old_version, new_version);
        if (changelog.length > 0)
            notable_changes ~= NotableChanges(name, old_version, new_version, changelog.dup);
    }

    unittest {
        import unit_threaded.assertions;
        import thepath: Path;
        import odood.utils.odoo.std_version: OdooStdVersion;

        auto ver = OdooStdVersion("17.0.1.0.0");

        // Empty changes: has_changes is false
        auto c = new AddonRepositoryChanges(ver);
        c.has_changes.shouldBeFalse;

        // Added addon triggers has_changes
        auto c_add = new AddonRepositoryChanges(ver);
        c_add.logAddonAdded("a", Path("a"), ver);
        c_add.has_changes.shouldBeTrue;

        // Removed addon triggers has_changes
        auto c_rem = new AddonRepositoryChanges(ver);
        c_rem.logAddonRemoved("a");
        c_rem.has_changes.shouldBeTrue;

        // Updated addon triggers has_changes
        auto c_upd = new AddonRepositoryChanges(ver);
        c_upd.logAddonUpdated("a", Path("a"), Path("a"), ver, ver, []);
        c_upd.has_changes.shouldBeTrue;
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
