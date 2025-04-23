module odood.lib.deploy.templates.logrotate;

import std.conv: text;

import odood.lib.project: Project;


string generateLogrotateDConfig(in Project project) {
    return i"$(project.directories.log.toString)/*.log {
    maxsize 50M
    rotate 5
    compress
    copytruncate
    missingok
    notifempty
}".text;
}

