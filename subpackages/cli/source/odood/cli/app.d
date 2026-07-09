module odood.cli.app;

private import std.logger;
private import std.format: format;

private import darkcommand;
private import colored;

private import odood.lib: _version;
private import odood.exception: OdoodException;
private import odood.cli.core.logger: OdoodLogger;
private import odood.cli.commands.init: CommandInit;
private import odood.cli.commands.server: CommandServer;
private import odood.cli.commands.database: CommandDatabase;
private import odood.cli.commands.status: CommandStatus;
private import odood.cli.commands.addons: CommandAddons;
private import odood.cli.commands.repository: CommandRepository;
private import odood.cli.commands.config: CommandConfig;
private import odood.cli.commands.test: CommandTest;
private import odood.cli.commands.venv: CommandVenv;
private import odood.cli.commands.discover: CommandDiscover;
private import odood.cli.commands.script: CommandScript;
private import odood.cli.commands.psql: CommandPSQL;
private import odood.cli.commands.info: CommandInfo;
private import odood.cli.commands.odoo: CommandOdoo;
private import odood.cli.commands.precommit: CommandPreCommit;
private import odood.cli.commands.translations: CommandTranslations;
private import odood.cli.commands.assembly: CommandAssembly;

version(linux) private import odood.cli.commands.deploy: CommandDeploy;


/** Class that represents main OdoodProgram
  **/
class App: Program {

    int verbose;
    int quiet;
    bool enable_debug;
    version(OdoodInDocker) bool configFromEnv;

    this() {
        super("odood", _version);
        this.summary("Easily manage odoo installations.");

        this.addFlag!(verbose)("v", "verbose", "Enable verbose output");
        this.addFlag!(quiet)("q", "quiet", "Hide unnecessary output");
        this.addFlag!(enable_debug)("d", "debug", "Show additional debug information.");

        version(OdoodInDocker)
            this.addFlag!(configFromEnv)(
                "", "config-from-env",
                "Apply odoo configuration from environment");

        {
            auto g = this.topicGroup("Main");
            g.add(new CommandInit());
            version(linux) g.add(new CommandDeploy());
            g.add(new CommandServer());
            g.add(new CommandStatus());
            g.add(new CommandDatabase());
            g.add(new CommandAddons());
            g.add(new CommandTest());
            g.add(new CommandRepository());
            g.add(new CommandVenv());
            g.add(new CommandOdoo());
            g.add(new CommandAssembly());
        }

        {
            auto g = this.topicGroup("Dev Tools");
            g.add(new CommandScript());
            g.add(new CommandPSQL());
            g.add(new CommandPreCommit());
            g.add(new CommandTranslations());
        }

        {
            auto g = this.topicGroup("System");
            g.add(new CommandConfig());
            g.add(new CommandDiscover());
            g.add(new CommandInfo());
        }

        this.addShortcut("start",   ["server", "start"],         "Run the server in background.");
        this.addShortcut("stop",    ["server", "stop"],          "Stop the server.");
        this.addShortcut("restart", ["server", "restart"],       "Restart the server.");
        this.addShortcut("browse",  ["server", "browse"],        "Open odoo in browser.");
        this.addShortcut("log",     ["server", "log"],           "View server logs.");
        this.addShortcut("lsd",     ["db",     "list"],          "Show databases.");
        this.addShortcut("lsa",     ["addons", "list"],          "List addons.");
        this.addShortcut("ual",     ["addons", "update-list"],   "Update list of addons.");
        this.addShortcut("tr",      ["translations"],             "Manage translations.");
    }

    void setUpLogging(in int verbosity, in int quietness) {
        auto log_verbosity = verbosity - quietness;

        LogLevel log_level;
        if (log_verbosity >= 2)
            log_level = LogLevel.all;
        else if (log_verbosity >= 1)
            log_level = LogLevel.trace;
        else if (log_verbosity >= 0)
            log_level = LogLevel.info;
        else if (log_verbosity >= -1)
            log_level = LogLevel.warning;
        else
            log_level = LogLevel.error;

        std.logger.sharedLog = cast(shared) new OdoodLogger(log_level);
    }

    version(OdoodInDocker) void applyOdooConfFromEnv() {
        import odood.project: Project;
        auto project = Project.maybeLoadProject;
        if (project.isNull) {
            warningf("Cannot load Odood project config. Cannot configure Odoo from env. Skipping...");
        } else {
            import std.process: environment;
            import std.string: chompPrefix, toLower, startsWith;
            infof("Applying configuration from env variables to Odoo config...");
            auto config = project.get.server.getConfig;
            foreach(kv; environment.toAA.byKeyValue) {
                if (!kv.key.toLower.startsWith("odood_opt_"))
                    continue;
                string key = kv.key.toLower.chompPrefix("odood_opt_");
                config["options"].setKey(key, kv.value);
                environment.remove(kv.key);
            }
            config.save(project.get.odoo.configfile.toString);
            infof("Odoo config updated from environment variables");
        }
    }

    override protected void setup() {
        import std.stdio;
        stdout.setvbuf(1024, _IONBF);
        stderr.setvbuf(1024, _IONBF);

        setUpLogging(verbose, quiet);

        version(OdoodInDocker) if (configFromEnv) applyOdooConfFromEnv();
    }

    override protected int onError(Exception e) {
        import std.stdio: stderr;

        if (enable_debug) {
            error("Exception caught:\n%s".format(e));
            return 1;
        }
        if (cast(DarkCommandException) e) {
            auto code = super.onError(e);
            if (cast(UnknownCommandException) e)
                stderr.writeln("Run 'odood --help' for a list of available commands.");
            return code;
        }
        error("%s".format(e.msg));
        return 1;
    }
}
