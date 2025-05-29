/** This module contains translation-related commands
  **/
module odood.cli.commands.translations;

private import std.exception: enforce;
private import std.format: format;
private import std.logger: infof, warningf, tracef;
private import std.algorithm: map;
private import std.array: join;

private import commandr: Argument, Option, Flag, ProgramArgs, acceptsValues;
private import thepath: Path;
private import theprocess: Process, resolveProgram;

private import odood.cli.core: OdoodCommand, OdoodCLIException;
private import odood.lib.project: Project;
private import odood.utils.addons.addon: OdooAddon;
private import odood.exception: OdoodException;
private import odood.utils: generateRandomString;


class CommandTranslationsRegenerate: OdoodCommand {

    protected struct LangInfo {
        string lang;
        string file;

        auto toString() {
            return lang ~ ":" ~ file;
        }
    }

    this() {
        super("regenerate", "Regenerate translations for specified addons.");
        this.add(new Flag(
            null, "pot-remove-dates", "Remove dates from generated .pot file."));
        this.add(new Flag(
            null, "pot", "Generate .pot file for translations."));
        this.add(new Flag(
            null, "pot-update", "Update translations based on regenerated .pot file."));
        this.add(new Flag(
            null, "missing-only", "Generate only missing translations."));

        // No drop db
        this.add(new Flag(
            null, "no-drop-db", "Do not drop database after regeneration of translations"));

        // Search for addons options
        this.add(new Option(
            null, "addon-dir", "Directory to search for addons").repeating);
        this.add(new Option(
            null, "addon-dir-r",
            "Directory to recursively search for addons").repeating);
        this.add(new Argument(
            "addon", "Specify names of addons as arguments.").optional.repeating);

        // Languages to translate
        this.add(new Option(
            null, "lang-file", "Combination of lang and file (separated by ':') to generate translations for. For example: uk_UA:uk.").repeating.required);
    }

    /** Find addons to regenerate translations for
      **/
    protected auto findAddons(ProgramArgs args, in Project project) {
        OdooAddon[] addons;
        foreach(search_path; args.options("addon-dir"))
            foreach(addon; project.addons.scan(Path(search_path), false))
                if (project.addons.isLinked(addon) && addon.manifest.installable)
                    addons ~= addon;
                else
                    warningf("Skip addon %s because it is not linked or not installable", addon);

        foreach(search_path; args.options("addon-dir-r"))
            foreach(addon; project.addons.scan(Path(search_path), true))
                if (project.addons.isLinked(addon) && addon.manifest.installable)
                    addons ~= addon;
                else
                    warningf("Skip addon %s because it is not linked or not installable", addon);

        foreach(addon_name; args.args("addon")) {
            auto addon = project.addons.getByString(addon_name);
            enforce!OdoodCLIException(
                !addon.isNull,
                "Cannot find addon %s!".format(addon_name));
            enforce!OdoodCLIException(
                project.addons.isLinked(addon.get),
                "Addon %s is not linked!".format(addon_name));
            enforce!OdoodCLIException(
                addon.get.manifest.installable,
                "Addon %s is not installable!".format(addon_name));
            addons ~= addon.get;
        }
        return addons;
    }

    protected LangInfo[] parseLangs(ProgramArgs args) {
        import std.array: split;
        LangInfo[] res;
        foreach(lf; args.options("lang-file")) {
            auto lfs = lf.split(':');
            enforce!OdoodException(
                lfs.length == 2,
                "Incorrect specification of lang-file option '%s'. Correct format is 'uk_UA:uk'.".format(lf));
            res ~= LangInfo(
                lang: lfs[0],
                file: lfs[1],
            );
        }
        return res;
    }

    public override void execute(ProgramArgs args) {
        auto project = Project.loadProject;

        auto addons = findAddons(args, project);
        auto langs = parseLangs(args);

        enforce!OdoodException(
            !resolveProgram("msgmerge").isNull,
            "This command requires 'msgmerge' program to work. Please, install 'gettext' package to get this utility.");

        auto dbname = "odood%s-test-%s".format(
            project.odoo.serie.major, generateRandomString(8));
        scope(exit) {
            // Drop temporary database on exit
            if (!args.flag("no-drop-db") && project.databases.exists(dbname))
                project.databases.drop(dbname);
        }

        project.databases.create(name: dbname, demo: true, lang: langs.map!((a) => a.lang).join(','));

        // Install required addons
        project.addons.install(dbname, addons);

        // Regenerate translations for addons
        foreach(addon; addons) {
            auto i18n_dir = addon.path.join("i18n");
            auto i18n_pot_file = i18n_dir.join("%s.pot".format(addon.name));

            if (!i18n_dir.exists)
                i18n_dir.mkdir(true);

            if (args.flag("pot")) {
                project.lodoo.generatePot(
                        dbname: dbname,
                        addon: addon.name,
                        remove_dates: args.flag("pot-remove-dates")
                );
            }

            // Update translations for specified langs
            foreach(li; langs) {
                auto i18n_file = i18n_dir.join("%s.po".format(li.file));

                if (args.flag("missing-only") && i18n_file.exists && args.flag("pot-update") && i18n_pot_file.exists) {
                    infof("translation file %s already exists. Updating translations based on .pot file.", i18n_file);
                    auto msgmerge = Process("msgmerge")
                        .withArgs(
                            "--quiet", "-N", "-U",
                            i18n_file.toString,
                            i18n_pot_file.toString);
                    tracef("Running %s", msgmerge);
                    msgmerge.execute.ensureOk!OdoodException(true);
                } else if (args.flag("missing-only") && i18n_file.exists) {
                    warningf(
                        "translation file %s already exists and --missing-only option enabled. Skipping translation %s for module %s.",
                        i18n_file, li, addon);
                } else {
                    infof("Generating translations for module %s for language %s...", addon, li);
                    auto cmd = project.server.getServerRunner(
                        "-d", dbname,
                        "--i18n-export=%s".format(i18n_file),
                        "--modules=%s".format(addon.name),
                        "--lang=%s".format(li.lang),
                        "--stop-after-init",
                        "--pidfile=",
                    );
                    tracef("Running %s", cmd);
                    cmd.execute.ensureOk(true);
                }
            }
        }


    }

}


class CommandTranslations: OdoodCommand {
    this(in string name) {
        super(name, "Manage translations for this project.");
        this.add(new CommandTranslationsRegenerate());
    }
    this() {
        this("translations");
    }
}
