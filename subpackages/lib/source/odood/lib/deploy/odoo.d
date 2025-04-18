module odood.lib.deploy.odoo;

private import core.sys.posix.unistd: geteuid, getegid;
private import core.sys.posix.pwd: getpwnam, passwd;

private import std.logger: infof;
private import std.exception: enforce, errnoEnforce;
private import std.conv: to, text, octal;
private import std.format: format;
private import std.string: toStringz, empty;

private import thepath: Path;
private import theprocess: Process;

private import odood.utils.odoo.serie: OdooSerie;
private import odood.lib.project: Project, ODOOD_SYSTEM_CONFIG_PATH;
private import odood.lib.project.config: ProjectServerSupervisor;

private import odood.lib.deploy.config: DeployConfig;
private import odood.lib.deploy.templates.init: generateInitDConfig;
private import odood.lib.deploy.templates.system: generateSystemDConfig;
private import odood.lib.deploy.templates.logrotate: generateLogrotateDConfig;
private import odood.lib.deploy.templates.nginx: generateNginxConfig;
private import odood.lib.deploy.templates.fail2ban: generateFail2banFilter, generateFail2banJail;
private import odood.lib.deploy.utils:
    checkSystemUserExists,
    createSystemUser,
    postgresCheckUserExists,
    postgresCreateUser;


private void deployInitScript(in Project project) {

    infof("Configuring init script for Odoo...");

    // Configure init scripts
    project.odoo.server_init_script_path.writeFile(
        generateInitDConfig(project));

    // Set access rights for init script
    project.odoo.server_init_script_path.setAttributes(octal!755);
    project.odoo.server_init_script_path.chown("root", "root");

    // Enable init script for Odoo
    Process("update-rc.d")
        .withArgs("odoo", "defaults")
        .execute
        .ensureOk(true);
    infof("Init script configred successfully. Odoo will be started at startup.");
}


private void deploySystemdConfig(in Project project) {

    infof("Configuring systemd daemon for Odoo...");

    // Configure systemd
    project.odoo.server_systemd_service_path.writeFile(
        generateSystemDConfig(project));

    // Set access rights for systemd config
    project.odoo.server_systemd_service_path.setAttributes(octal!755);
    project.odoo.server_systemd_service_path.chown("root", "root");

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


private void deployLogrotateConfig(in Project project, in DeployConfig config) {
    infof("Configuring logrotate for Odoo...");

    config.logrotate_config_path.writeFile(generateLogrotateDConfig(project));

    // Set access rights for logrotate config
    config.logrotate_config_path.setAttributes(octal!755);
    config.logrotate_config_path.chown("root", "root");

    infof("Logrotate configured successfully.");
}


/** Deploy nginx configuration for Odoo
  **/
private void deployNginxConfig(in Project project, in DeployConfig config) {
    infof("Configuring Nginx for Odoo...");

    config.nginx_config_path.writeFile(
        generateNginxConfig(
            odoo_address: config.odoo.http_host.empty ? "127.0.0.1" : config.odoo.http_host,
            odoo_port: config.odoo.http_port,
        )
    );

    // Set access rights for logrotate config
    config.nginx_config_path.setAttributes(octal!644);
    config.nginx_config_path.chown("root", "root");

    // Remove default nginx configuration, thus Odoo will work out-of-the-box
    if (config.local_nginx_disable_default) {
        auto nginx_default = Path("/", "etc", "nginx", "sites-enabled", "default");
        auto nginx_default_base = Path("/", "etc", "nginx", "sites-available", "default");
        if (nginx_default.exists &&
                nginx_default_base.exists &&
                nginx_default.readLink == nginx_default_base)
            nginx_default.remove();
    }

    // Reload nginx
    Process("systemctl")
        .withArgs("reload", "nginx.service")
        .execute
        .ensureOk(true);

    infof("Nginx configured successfully.");
}


/** Deploy fail2ban configuration for Odoo
  **/
private void deployFail2banConfig(in Project project, in DeployConfig config) {
    infof("Configuring Fail2ban for Odoo...");

    config.fail2ban_filter_path.writeFile(generateFail2banFilter(project));

    // Set access rights for logrotate config
    config.fail2ban_filter_path.setAttributes(octal!644);
    config.fail2ban_filter_path.chown("root", "root");

    config.fail2ban_jail_path.writeFile(generateFail2banJail(project));

    // Set access rights for logrotate config
    config.fail2ban_filter_path.setAttributes(octal!644);
    config.fail2ban_jail_path.chown("root", "root");

    // Reload nginx
    Process("systemctl")
        .withArgs("reload", "fail2ban.service")
        .execute
        .ensureOk(true);

    infof("Fail2ban configured successfully.");
}


/** Deploy Odoo according provided DeployConfig
  **/
Project deployOdoo(in DeployConfig config) {
    infof("Deploying Odoo %s to %s", config.odoo.serie, config.deploy_path);

    // TODO: Move this configuration to Deploy config
    auto project = config.prepareOdoodProject();

    // We need to keep reference on odoo_config to make initialize work.
    // TODO: Fix this
    auto odoo_config = config.prepareOdooConfig(project);

    // Initialize project.
    project.initialize(
        odoo_config,
        config.venv_options,
        config.install_type);
    project.save(ODOOD_SYSTEM_CONFIG_PATH);

    if (!checkSystemUserExists(project.odoo.server_user))
        createSystemUser(project.project_root, project.odoo.server_user);

    // Get info about odoo user (that is needed to set up access rights for Odoo files
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

    // Existing file is required to make fail2ban work.
    // Thus we just create empty logfile here, odoo will continue to log here
    if (!project.odoo.logfile.exists) {
        project.odoo.logfile.writeFile([]);
        project.odoo.logfile.chown(pw_odoo.pw_uid, pw_odoo.pw_gid);
        project.odoo.logfile.setAttributes(octal!640);
    }

    // Make Odoo owner of data directory. Do not allow others to access it.
    project.directories.data.chown(pw_odoo.pw_uid, pw_odoo.pw_gid);
    project.directories.data.setAttributes(octal!750);

    // Make Odoo owner of project root (/opt/odoo), but not recursively,
    // thus, Odoo will be able to create files there,
    // but will not be allowed to change existing files.
    project.project_root.chown(pw_odoo.pw_uid, pw_odoo.pw_gid);

    // Create postgresql user if "local-postgres" is selected and no user exists
    if (config.database.local_postgres)
        /* In this case we need to create postgres user
         * only if it does not exists yet.
         * If user already exists, we expect,
         * that user provided correct password for it.
         */
        if (!postgresCheckUserExists(config.database.user))
            postgresCreateUser(config.database.user, config.database.password);

    // Configure logrotate
    if (config.logrotate_enable)
        deployLogrotateConfig(project, config);

    // Configure systemd
    final switch(config.odoo.server_supervisor) {
        case ProjectServerSupervisor.Odood:
            // Do nothing.
            // TODO: May be it have sense to create some link in /usr/sbin for Odoo?
            break;
        case ProjectServerSupervisor.InitScript:
            deployInitScript(project);
            break;
        case ProjectServerSupervisor.Systemd:
            deploySystemdConfig(project);
            break;
    }

    // Deploy nginx
    if (config.local_nginx)
        deployNginxConfig(project, config);

    // Deploy fail2ban
    if (config.fail2ban_enable)
        deployFail2banConfig(project, config);

    infof("Odoo deployed successfully.");
    return project;
}



