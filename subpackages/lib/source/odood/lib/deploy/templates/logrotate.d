module odood.lib.deploy.templates.logrotate;

import std.conv: text;

import odood.lib.project: Project;


string generateLogrotateDConfig(in Project project) {
    // TODO: Set max size and rotate
    return i"$(project.directories.log.toString)/*.log {
    copytruncate
    missingok
    notifempty
}".text;
}

