module odood.lib.install.project;

private import odood.lib.project: Project;


/** Initialize project directory structure for specified project.
    This function will create all needed directories for project.

    Params:
        project = Instance of Odood Project to initialize directory structure.
 **/
void initializeProjectDirs(in Project project) {
    project.project_root.mkdir(true);
    project.directories.conf.mkdir(true);
    project.directories.log.mkdir(true);
    project.directories.downloads.mkdir(true);
    project.directories.addons.mkdir(true);
    project.directories.data.mkdir(true);
    project.directories.backups.mkdir(true);
    project.directories.repositories.mkdir(true);
}



