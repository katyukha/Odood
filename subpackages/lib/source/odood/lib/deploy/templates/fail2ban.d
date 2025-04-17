module odood.lib.deploy.templates.fail2ban;

private import std.conv: text;

private import odood.lib.project: Project;


string generateFail2banFilter(in Project project) {
    return `
[Definition]
failregex = ^ \d+ INFO \S+ \S+ Login failed for db:\S+ login:\S+ from <HOST>
            ^ \d+ INFO \S+ \S+ Password reset attempt for \S+ by user \S+ from <HOST>
ignoreregex =
`;
}


string generateFail2banJail(in Project project) {
    return i"
[odoo-auth]
enabled = true
port = http,https
bantime = 900
bantime.increment = true
maxretry = 4
findtime = 300
backend = auto
logpath = $(project.odoo.logfile.toString)
    ".text;
}


