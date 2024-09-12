module odood.lib.deploy.odoo;

private import core.sys.posix.unistd: geteuid, getegid;
private import core.sys.posix.pwd: getpwnam, passwd;

private import std.logger: infof;
private import std.exception: enforce, errnoEnforce;
private import std.conv: text, octal;
private import std.format: format;

private import thepath: Path;
private import theprocess: Process;

private import odood.utils.odoo.serie: OdooSerie;
private import odood.lib.project: Project, ODOOD_SYSTEM_CONFIG_PATH;
private import odood.lib.project.config:
    ProjectConfigDirectories, ProjectConfigOdoo;

private import odood.lib.deploy.config: DeployConfig;
private import odood.lib.deploy.utils: checkSystemUserExists, createSystemUser;


immutable auto ODOO_SYSTEMD_PATH = Path(
    "/", "etc", "systemd", "system", "odoo.service");

private void deploySystemdConfig(in Project project) {

    infof("Configuring systemd daemon for Odoo...");

    // Configure systemd
    ODOO_SYSTEMD_PATH.writeFile(
i"[Unit]
Description=Odoo Open Source ERP and CRM
After=network.target

[Service]
Type=simple
User=$(project.odoo.server_user)
Group=$(project.odoo.server_user)
ExecStart=%(project.server.scriptPath) --config $(project.odoo.configfile)
KillMode=mixed

[Install]
WantedBy=multi-user.target
".text);

    // Set access rights for systemd config
    ODOO_SYSTEMD_PATH.setAttributes(octal!755);
    ODOO_SYSTEMD_PATH.chown("root", "root");

    // Enable systemd service for Odoo
    Process("systemctl")
        .withArgs("daemon-reload")
        .execute
        .ensureOk(true);
    Process("systemctl")
        .withArgs("enable", "--now", "odoo.service")
        .execute
        .ensureOk(true);
    Process("systemctl")
        .withArgs("start", "odoo.service")
        .execute
        .ensureOk(true);

    infof("Systemd configred successfully. Odoo will be started at startup.");
}


private void deployLogrotateConfig(in Project project) {
    immutable auto logrotate_config_path = Path("/", "etc", "logrotate.d", "odoo");

    infof("Configuring logrotate for Odoo...");
    logrotate_config_path.writeFile(
i"$(project.directories.log.toString)/*.log {
    copytruncate
    missingok
    notifempty
}".text);

    // Set access rights for logrotate config
    logrotate_config_path.setAttributes(octal!755);
    logrotate_config_path.chown("root", "root");

    infof("Logrotate configured successfully.");
}

private void setAccessRights(in Project project) {
    import std.string: toStringz;
    // Get info about odoo user
    auto pw_odoo = getpwnam(project.odoo.server_user.toStringz);
    errnoEnforce(
        pw_odoo !is null,
        "Cannot get info about user %s".format(project.odoo.server_user));

    // Config is owned by root, but readable by Odoo
    project.odoo.configfile.chown(0, pw_odoo.pw_gid);
    project.odoo.configfile.setAttributes(octal!640);

    // Odoo can read and write and create files in log directory
    project.directories.log.chown(pw_odoo.pw_uid, pw_odoo.pw_gid);
    project.directories.log.setAttributes(octal!750);

    // Make Odoo owner of data directory. Do not allow others to access it.
    project.directories.data.chown(pw_odoo.pw_uid, pw_odoo.pw_gid);
    project.directories.data.setAttributes(octal!750);

    // Make Odoo owner of project root (/opt/odoo), but not recursively,
    // thus, Odoo will be able to create files there,
    // but will not be allowed to change existing files.
    project.project_root.chown(pw_odoo.pw_uid, pw_odoo.pw_gid);
}

Project deployOdoo(in DeployConfig config) {
    infof("Deploying Odoo %s to %s", config.odoo.serie, config.deploy_path);

    // TODO: Move this configuration to Deploy config
    auto project_directories = ProjectConfigDirectories(config.deploy_path);
    auto project_odoo = ProjectConfigOdoo(
        config.deploy_path, project_directories, config.odoo.serie);
    project_odoo.server_user = config.odoo.server_user;
    project_odoo.server_supervisor = config.odoo.server_supervisor;
    project_odoo.server_systemd_service_path = ODOO_SYSTEMD_PATH;

    auto project = new Project(
        config.deploy_path,
        project_directories,
        project_odoo);

    auto odoo_config = config.prepareOdooConfig(project);
    project.initialize(
        odoo_config,
        config.py_version,
        config.node_version,
        config.install_type);
    project.save(ODOOD_SYSTEM_CONFIG_PATH);

    if (!checkSystemUserExists(project.odoo.server_user))
        createSystemUser(project.project_root, project.odoo.server_user);

    // Set access rights for Odoo installed
    project.setAccessRights();

    // Configure logrotate
    // TODO: make it optional
    deployLogrotateConfig(project);

    // Configure systemd
    // TODO: make it optional
    deploySystemdConfig(project);

    infof("Odoo deployed successfully.");
    return project;
}



