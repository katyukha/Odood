module odood.lib.project;

private import thepath: Path;
private static import dyaml; 

private import odood.lib.exception: OdoodException;

public import odood.lib.project_config: ProjectConfig;


struct Project {
    private ProjectConfig _config;

    /** Initialize by path.

        Params:
            path = is path to odood config file or path to directory
                that contains odood.yml config file
     **/
    this(in Path path) {
        if (path.exists && path.isFile) {
            _config.load(path);
        } if (path.exists && path.isDir && path.join("odood.yml").exists) {
            _config.load(path.join("odood.yml"));
        } else {
            throw new OdoodException(
                "Cannot initialize project. Config not found");
        }
    }

    /** Initialize by provided config

        Params:
            cofnig = instance of project configuration to initialize from.
     **/
    this(in ProjectConfig config) {
        _config = config;
    }

    @property const (ProjectConfig) config() const { return _config; }

    /** Save project configuration to config file.

        Params:
           path = path to config file to save configuration to.
     **/
    void save(in Path path = Path()) {
        if (path.isNull) _config.save(_config.root_dir.join("odood.yml"));
        else _config.save(path);
    }

    /** Initialize project.
     **/
    void initialize() {
        import odood.lib.install;

        _config.initializeProjectDirs();
        _config.installDownloadOdoo();
        _config.installVirtualenv();
        _config.installOdoo();

        // 1. Prepare directory structure
        // 2. Install Odoo
        // 3. Install virtualenv
        // 4. Install python dependencies

    }
}
