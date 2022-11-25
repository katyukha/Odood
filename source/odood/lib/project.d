module odood.lib.project;

private import thepath: Path;
private static import dyaml; 

private import odood.lib.exception: OdoodException;

public import odood.lib.project_config: ProjectConfig;


struct Project {
    private ProjectConfig config;

    /** Initialize by path.

        Params:
            path = is path to odood config file or path to directory
                that contains odood.yml config file
     **/
    this(in Path path) {
        if (path.exists && path.isFile) {
            this.loadConfig(path);
        } if (path.exists && path.isDir) {
            this.loadConfig(path.join("odood.yml"));
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
        this.config = config;
    }

    /** Load configuration from config file.

        Params:
            path = path to config file to load.
     **/

    void loadConfig(in Path path) {
        this.config.load(path);
    }

    /** Save project configuration to config file.

        Params:
           path = path to config file to save configuration to.
     **/
    void saveConfig(in Path path) {
        this.config.save(path);
    }
}
