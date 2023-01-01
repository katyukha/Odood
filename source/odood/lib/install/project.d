module odood.lib.install.project;

private import odood.lib.project.config: ProjectConfig;


/** Initialize project directory structure for specified project config.
    This function will create all needed directories for project.

    Params:
        config = Project configuration to initialize directory structure.
 **/
void initializeProjectDirs(in ProjectConfig config) {
    config.project_root.mkdir(true);
    config.conf_dir.mkdir(true);
    config.log_dir.mkdir(true);
    config.downloads_dir.mkdir(true);
    config.addons_dir.mkdir(true);
    config.data_dir.mkdir(true);
    config.backups_dir.mkdir(true);
    config.repositories_dir.mkdir(true);
}



