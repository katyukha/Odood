module odood.lib.deploy.templates.nginx;

import std.conv: text;
import std.format: format;


string generateNginxConfig(in string odoo_address, in string odoo_port, in string server_name=null) {
    return i`
upstream odoo_backend {
        server $(odoo_address):$(odoo_port) weight=1 fail_timeout=2000s;
}

upstream odoo_websocket {
        server $(odoo_address):$(odoo_port) weight=1 fail_timeout=300s;
}

#------------------------------------------------------------------------------
# Add mapping for $connection_upgrade variable
#------------------------------------------------------------------------------
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}


# Force SSL (HTTPS)
#server {
    #listen   :80;
    #$(server_name ? "server_name %s;".format(server_name) : "")

    #location / {
        #return 301 https://$host$request_uri;
    #}
#}

server {
    listen   :80;
    # listen   :443 ssl;
    $(server_name ? "server_name %s;".format(server_name) : "")

    #-----------------------------------------------------------------------
    access_log  /var/log/nginx/odoo.access.log;
    error_log   /var/log/nginx/odoo.error.log;
    #-----------------------------------------------------------------------

    #-----------------------------------------------------------------------
    # SSL config
    #ssl on;
    #ssl_certificate  /etc/nginx/ssl/server.crt;
    #ssl_certificate_key /etc/nginx/ssl/server.key;
    #-----------------------------------------------------------------------

    #-----------------------------------------------------------------------
    # global params for Odoo backend server section
    client_max_body_size 100m;

    # Proxy global settings
    # increase proxy buffer to handle some OpenERP web requests
    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    # general proxy settings
    # force timeouts if the backend dies
    proxy_connect_timeout 900s;
    proxy_send_timeout 900s;
    proxy_read_timeout 900s;
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

    # set headers
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forward-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;


    # by default, do not forward anything
    proxy_redirect off;
    proxy_buffering off;

    # use gzip for folowing types
    gzip_types text/html text/css text/less text/plain text/xml application/xml application/json application/javascript;
    #-----------------------------------------------------------------------


    location / {
        # add_header Content-Security-Policy "upgrade-insecure-requests";
        proxy_pass http://odoo_backend;
    }

    # Chat and IM related features support
    location /websocket {
	    # add_header Content-Security-Policy "upgrade-insecure-requests";
        proxy_pass http://odoo_websocket;

        # Upgrade connection
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
    }

    # Restrict access
    location ~* ^/(web/database/|web/tests) {
        # TODO: Restrict external access here
        #    allow trusted_network;
        #    allow trusted_ip;
        #    deny all;
        # add_header Content-Security-Policy "upgrade-insecure-requests";
        # deny all;
        proxy_pass http://odoo_backend;
    }
    location ~* ^/(jsonrpc|xmlrpc) {
        # TODO: Restrict external access here
        #    allow trusted_network;
        #    allow trusted_ip;
        #    deny all;
	    # add_header Content-Security-Policy "upgrade-insecure-requests";
        proxy_pass http://odoo_backend;
    }

    # cache some static data in memory for 60mins.
    # under heavy load this will preserve the OpenERP Web client a little bit.
    location /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_buffering    on;
        expires 864000;
        # add_header Content-Security-Policy "upgrade-insecure-requests";
        proxy_pass         http://odoo_backend;
    }
}
`.text;
}
