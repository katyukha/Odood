module odood.lib.install.project;

private import odood.lib.project.config: ProjectConfig;


/** Initialize project directory structure for specified project config.
    This function will create all needed directories for project.

    Params:
        config = Project configuration to initialize directory structure.
 **/
void initializeProjectDirs(in ProjectConfig config) {
    config.project_root.mkdir(true);
    config.directories.conf.mkdir(true);
    config.directories.log.mkdir(true);
    config.directories.downloads.mkdir(true);
    config.directories.addons.mkdir(true);
    config.directories.data.mkdir(true);
    config.directories.backups.mkdir(true);
    config.directories.repositories.mkdir(true);
}



