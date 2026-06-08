/** This module contains translation-related commands
  **/
module odood.cli.commands.translations;

private import std.exception: enforce;
private import std.format: format;
private import std.logger: infof, warningf, tracef;
private import std.algorithm: map;
private import std.array: join;

private import darkcommand;
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

    bool potRemoveDates;
    bool pot;
    bool potUpdate;
    bool missingOnly;
    bool noDropDb;
    Path[] addonDir;
    Path[] addonDirR;
    string[] addon;
    string[] langFile;
    string[] lang;

    this() {
        super("regenerate", "Regenerate translations for specified addons.");
        this.addFlag!(potRemoveDates)("", "pot-remove-dates",
            "Remove dates from generated .pot file.");
        this.addFlag!(pot)("", "pot", "Generate .pot file for translations.");
        this.addFlag!(potUpdate)("", "pot-update",
            "Update translations based on regenerated .pot file.");
        this.addFlag!(missingOnly)("", "missing-only",
            "Generate only missing translations.");
        this.addFlag!(noDropDb)("", "no-drop-db",
            "Do not drop database after regeneration of translations");
        this.addOption!(addonDir)("", "addon-dir",
            "Directory to search for addons")
            .acceptsDirectories();
        this.addOption!(addonDirR)("", "addon-dir-r",
            "Directory to recursively search for addons")
            .acceptsDirectories();
        this.addOption!(langFile)("", "lang-file",
            "Combination of lang and file (separated by ':') to generate translations for. For example: uk_UA:uk.");
        this.addOption!(lang)("l", "lang",
            "Language to generate translations for. For example: uk_UA.");
        this.addArgument!(addon)("addon", "Names of addons to regenerate translations for.")
            .defaultValue([]);
    }

    protected auto findAddons(in Project project) {
        OdooAddon[] addons;
        foreach(search_path; addonDir)
            foreach(a; project.addons.scan(search_path, false))
                if (project.addons.isLinked(a) && a.manifest.installable)
                    addons ~= a;
                else
                    warningf("Skip addon %s because it is not linked or not installable", a);

        foreach(search_path; addonDirR)
            foreach(a; project.addons.scan(search_path, true))
                if (project.addons.isLinked(a) && a.manifest.installable)
                    addons ~= a;
                else
                    warningf("Skip addon %s because it is not linked or not installable", a);

        foreach(addon_name; addon) {
            auto a = project.addons.getByString(addon_name);
            enforce!OdoodCLIException(
                !a.isNull,
                "Cannot find addon %s!".format(addon_name));
            enforce!OdoodCLIException(
                project.addons.isLinked(a.get),
                "Addon %s is not linked!".format(addon_name));
            enforce!OdoodCLIException(
                a.get.manifest.installable,
                "Addon %s is not installable!".format(addon_name));
            addons ~= a.get;
        }
        return addons;
    }

    protected LangInfo[] parseLangs() {
        import std.array: split;
        LangInfo[] res;
        foreach(lf; langFile) {
            auto lfs = lf.split(':');
            enforce!OdoodException(
                lfs.length == 2,
                "Incorrect specification of lang-file option '%s'. Correct format is 'uk_UA:uk'.".format(lf));
            res ~= LangInfo(
                lang: lfs[0],
                file: lfs[1],
            );
        }
        foreach(lg; lang) {
            auto ls = lg.split('_');
            enforce!OdoodException(
                ls.length == 2,
                "Incorrect specification of lang option '%s'. Correct format is 'uk_UA'.".format(lg));
            res ~= LangInfo(
                lang: lg,
                file: ls[0],
            );
        }
        return res;
    }

    override int execute() {
        auto project = Project.loadProject;

        auto addons = findAddons(project);
        auto langs = parseLangs();

        enforce!OdoodException(
            !resolveProgram("msgmerge").isNull,
            "This command requires 'msgmerge' program to work. Please, install 'gettext' package to get this utility.");
        enforce!OdoodException(
            langs.length > 0,
            "There must be specified at least one --lang option or --lang-file option.");
        enforce!OdoodException(
            addons.length > 0,
            "There must be at least 1 addon specified to regenerate translations for.");

        auto dbname = "odood%s-test-%s".format(
            project.odoo.serie.major, generateRandomString(8));
        scope(exit) {
            if (!noDropDb && project.databases.exists(dbname))
                project.databases.drop(dbname);
        }

        project.databases.create(name: dbname, demo: true, lang: langs.map!((a) => a.lang).join(','));

        project.addons.install(dbname, addons);

        foreach(a; addons) {
            auto i18n_dir = a.path.join("i18n");
            auto i18n_pot_file = i18n_dir.join("%s.pot".format(a.name));

            if (!i18n_dir.exists)
                i18n_dir.mkdir(true);

            if (pot || potUpdate) {
                project.lodoo.generatePot(
                        dbname: dbname,
                        addon: a.name,
                        remove_dates: potRemoveDates
                );
            }

            foreach(li; langs) {
                auto i18n_file = i18n_dir.join("%s.po".format(li.file));

                if (missingOnly && i18n_file.exists && potUpdate && i18n_pot_file.exists) {
                    infof("translation file %s already exists. Updating translations based on .pot file.", i18n_file);
                    // We have to uniquify translations first.
                    // Because AI frequently duplicates transaltions, and people do not care on that
                    auto msguniq = Process("msguniq")
                        .withArgs(
                            i18n_file.toString,
                            "--output-file=%s".format(i18n_file));
                    tracef("Running %s", msguniq);
                    msguniq.execute.ensureOk!OdoodException(true);
                    auto msgmerge = Process("msgmerge")
                        .withArgs(
                            "--quiet", "-N", "-U",
                            i18n_file.toString,
                            i18n_pot_file.toString);
                    tracef("Running %s", msgmerge);
                    msgmerge.execute.ensureOk!OdoodException(true);
                } else if (missingOnly && i18n_file.exists) {
                    warningf(
                        "translation file %s already exists and --missing-only option enabled. Skipping translation %s for module %s.",
                        i18n_file, li, a);
                } else {
                    infof("Generating translations for module %s for language %s...", a, li);
                    auto cmd = project.server.getServerRunner(
                        "-d", dbname,
                        "--i18n-export=%s".format(i18n_file),
                        "--modules=%s".format(a.name),
                        "--lang=%s".format(li.lang),
                        "--stop-after-init",
                        "--pidfile=",
                    );
                    tracef("Running %s", cmd);
                    cmd.execute.ensureOk(true);
                }
            }
        }
        return 0;
    }
}


class CommandTranslations: OdoodCommand {
    this() {
        super("translations", "Manage translations for this project.");
        this.add(new CommandTranslationsRegenerate());
    }
}
