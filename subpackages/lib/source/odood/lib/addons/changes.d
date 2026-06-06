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
      * Starting from `floor` (the least significant bump the caller allows),
      * the most significant signal wins:
      * - Removed addon                       → MAJOR (breaking).
      * - Added addon                         → MINOR (purely additive).
      * - Updated addon                       → escalated to its addon-version
      *                                         diff (MAJOR / MINOR / PATCH).
      * - Addon with a non-standard version   → floored to MINOR (cannot diff).
      *
      * No changes → version unchanged.
      *
      * Params:
      *     floor = least significant version part to bump
      *             (MAJOR / MINOR / PATCH); defaults to MINOR.
      **/
    void postProcess(in VersionPart floor = VersionPart.MINOR)
    in (floor == VersionPart.MAJOR
            || floor == VersionPart.MINOR
            || floor == VersionPart.PATCH) {
        if (!has_changes)
            return;

        // VersionPart severity: MAJOR=0 < MINOR=1 < PATCH=2. Start at the floor
        // and escalate toward MAJOR by the strongest signal.
        VersionPart vpart = floor;

        // A removal is breaking (MAJOR). An addition is additive: it floors the
        // bump to MINOR (a no-op when the floor is already MINOR or coarser).
        if (addons_removed.length > 0)
            vpart = VersionPart.MAJOR;
        else if (addons_added.length > 0 && vpart > VersionPart.MINOR)
            vpart = VersionPart.MINOR;

        // Updated addons escalate the bump to their most significant diff.
        foreach(addon; addons_updated) {
            if (vpart == VersionPart.MAJOR)
                break;
            if (!addon.old_version.isStandard || !addon.new_version.isStandard) {
                // Non-standard versions cannot be diffed; floor at MINOR.
                if (vpart > VersionPart.MINOR)
                    vpart = VersionPart.MINOR;
                continue;
            }
            if (addon.old_version == addon.new_version)
                continue;
            auto diff = addon.old_version.differAt(addon.new_version);
            if (diff < vpart)
                vpart = diff;
        }

        repo_version = repo_version.incVersion(vpart);
    }

    unittest {
        import unit_threaded.assertions;
        import thepath: Path;
        import odood.utils.odoo.std_version: OdooStdVersion;

        // Assembly versioning seeds at <serie>.0.0.0.
        auto base = OdooStdVersion("18.0.0.0.0");

        // No changes → version unchanged.
        auto a_none = new AddonRepositoryChanges(base);
        a_none.postProcess(VersionPart.PATCH);
        a_none.repo_version.toString.should == "18.0.0.0.0";

        // Added addon → MINOR (purely additive, same as release).
        auto a_add = new AddonRepositoryChanges(base);
        a_add.logAddonAdded("a", Path("a"), OdooStdVersion("18.0.1.0.0"));
        a_add.postProcess(VersionPart.PATCH);
        a_add.repo_version.toString.should == "18.0.0.1.0";

        // Removed addon → MAJOR.
        auto a_rem = new AddonRepositoryChanges(base);
        a_rem.logAddonRemoved("a");
        a_rem.postProcess(VersionPart.PATCH);
        a_rem.repo_version.toString.should == "18.0.1.0.0";

        // Updated addon, patch-level diff → PATCH (no reserved hotfix lane).
        auto a_patch = new AddonRepositoryChanges(base);
        a_patch.logAddonUpdated(
            "a", Path("a"), Path("a"),
            OdooStdVersion("18.0.1.0.0"), OdooStdVersion("18.0.1.0.1"), []);
        a_patch.postProcess(VersionPart.PATCH);
        a_patch.repo_version.toString.should == "18.0.0.0.1";

        // Updated addon, minor-level diff → MINOR.
        auto a_minor = new AddonRepositoryChanges(base);
        a_minor.logAddonUpdated(
            "a", Path("a"), Path("a"),
            OdooStdVersion("18.0.1.0.0"), OdooStdVersion("18.0.1.1.0"), []);
        a_minor.postProcess(VersionPart.PATCH);
        a_minor.repo_version.toString.should == "18.0.0.1.0";

        // Updated addon, major-level diff → MAJOR.
        auto a_major = new AddonRepositoryChanges(base);
        a_major.logAddonUpdated(
            "a", Path("a"), Path("a"),
            OdooStdVersion("18.0.1.0.0"), OdooStdVersion("18.0.2.0.0"), []);
        a_major.postProcess(VersionPart.PATCH);
        a_major.repo_version.toString.should == "18.0.1.0.0";
    }

    unittest {
        import unit_threaded.assertions;
        import thepath: Path;
        import odood.utils.odoo.std_version: OdooStdVersion;

        auto base = OdooStdVersion("17.0.1.0.0");

        // No changes → version unchanged.
        auto c_none = new AddonRepositoryChanges(base);
        c_none.postProcess();
        c_none.repo_version.toString.should == "17.0.1.0.0";

        // Added addon → MINOR (additive).
        auto c_add = new AddonRepositoryChanges(base);
        c_add.logAddonAdded("a", Path("a"), OdooStdVersion("17.0.1.0.0"));
        c_add.postProcess();
        c_add.repo_version.toString.should == "17.0.1.1.0";

        // Removed addon → MAJOR (breaking).
        auto c_rem = new AddonRepositoryChanges(base);
        c_rem.logAddonRemoved("a");
        c_rem.postProcess();
        c_rem.repo_version.toString.should == "17.0.2.0.0";

        // Updated addon, patch-level diff → MINOR (Z reserved for hotfixes).
        auto c_patch = new AddonRepositoryChanges(base);
        c_patch.logAddonUpdated(
            "a", Path("a"), Path("a"),
            OdooStdVersion("17.0.1.0.0"), OdooStdVersion("17.0.1.0.1"), []);
        c_patch.postProcess();
        c_patch.repo_version.toString.should == "17.0.1.1.0";

        // Updated addon, minor-level diff → MINOR.
        auto c_minor = new AddonRepositoryChanges(base);
        c_minor.logAddonUpdated(
            "a", Path("a"), Path("a"),
            OdooStdVersion("17.0.1.0.0"), OdooStdVersion("17.0.1.1.0"), []);
        c_minor.postProcess();
        c_minor.repo_version.toString.should == "17.0.1.1.0";

        // Updated addon, major-level diff → MAJOR.
        auto c_major = new AddonRepositoryChanges(base);
        c_major.logAddonUpdated(
            "a", Path("a"), Path("a"),
            OdooStdVersion("17.0.1.0.0"), OdooStdVersion("17.0.2.0.0"), []);
        c_major.postProcess();
        c_major.repo_version.toString.should == "17.0.2.0.0";
    }
}
