module odood.lib.deploy.odoo;

private import core.sys.posix.unistd: geteuid, getegid;
private import core.sys.posix.pwd: getpwnam, passwd;

private import std.logger: infof;
private import std.exception: enforce, errnoEnforce;
private import std.conv: to, text, octal;
private import std.format: format;
private import std.string: toStringz;

private import thepath: Path;
private import theprocess: Process;

private import odood.utils.odoo.serie: OdooSerie;
private import odood.lib.project: Project, ODOOD_SYSTEM_CONFIG_PATH;
private import odood.lib.project.config: ProjectServerSupervisor;

private import odood.lib.deploy.config: DeployConfig;
private import odood.lib.deploy.utils:
    checkSystemUserExists,
    createSystemUser,
    postgresCheckUserExists,
    postgresCreateUser;


private void deployInitScript(in Project project) {

    infof("Configuring init script for Odoo...");

    // Configure init scripts
    project.odoo.server_init_script_path.writeFile(
i"#!/bin/bash
### BEGIN INIT INFO
# Provides:          odoo
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start odoo daemon at boot time
# Description:       Enable service provided by daemon.
# X-Interactive:     true
### END INIT INFO
## more info: http://wiki.debian.org/LSBInitScripts

. /lib/lsb/init-functions

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin:$(project.venv.bin_path.toString)
DAEMON=$(project.server.scriptPath.toString)
    NAME=odoo
    DESC=odoo
    CONFIG=$(project.odoo.configfile.toString)
LOGFILE=$(project.odoo.logfile.toString)
PIDFILE=$(project.odoo.pidfile.toString).pid
USER=$(project.odoo.server_user)
export LOGNAME=$USER

test -x $DAEMON || exit 0
set -e

function _start() {
    start-stop-daemon --start --quiet --pidfile $PIDFILE --chuid $USER:$USER --background --make-pidfile --exec $DAEMON -- --config $CONFIG --logfile $LOGFILE
}

function _stop() {
    start-stop-daemon --stop --quiet --pidfile $PIDFILE --oknodo --retry 3
    rm -f $PIDFILE
}

function _status() {
    start-stop-daemon --status --quiet --pidfile $PIDFILE
    return $?
}


case \"$1\" in
        start)
                echo -n \"Starting $DESC: \"
                _start
                echo \"ok\"
                ;;
        stop)
                echo -n \"Stopping $DESC: \"
                _stop
                echo \"ok\"
                ;;
        restart|force-reload)
                echo -n \"Restarting $DESC: \"
                _stop
                sleep 1
                _start
                echo \"ok\"
                ;;
        status)
                echo -n \"Status of $DESC: \"
                _status && echo \"running\" || echo \"stopped\"
                ;;
        *)
                N=/etc/init.d/$NAME
                echo \"Usage: $N {start|stop|restart|force-reload|status}\" >&2
                exit 1
                ;;
esac

exit 0
".text);

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
i"[Unit]
Description=Odoo Open Source ERP and CRM
After=network.target

[Service]
Type=simple
User=$(project.odoo.server_user)
Group=$(project.odoo.server_user)
ExecStart=$(project.server.scriptPath) --config $(project.odoo.configfile)
KillMode=mixed

[Install]
WantedBy=multi-user.target
".text);

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
    config.logrotate_config_path.writeFile(
i"$(project.directories.log.toString)/*.log {
    copytruncate
    missingok
    notifempty
}".text);

    // Set access rights for logrotate config
    config.logrotate_config_path.setAttributes(octal!755);
    config.logrotate_config_path.chown("root", "root");

    infof("Logrotate configured successfully.");
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

    infof("Odoo deployed successfully.");
    return project;
}



