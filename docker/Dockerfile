FROM ubuntu:24.04

ARG ODOO_VERSION
ARG ODOOD_DEPENDENCIES

RUN apt-get update -qq && \
    apt-get install -qqq -y --no-install-recommends --auto-remove \
        locales \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        tzdata && \
    locale-gen en_US.UTF-8 && \
    locale-gen en_GB.UTF-8 && \
    update-locale LANG="en_US.UTF-8" && update-locale LANGUAGE="en_US:en" \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
            apt-key add - && \
	apt-get update -qq && \
    apt-get install -qqq -y --no-install-recommends --auto-remove $ODOOD_DEPENDENCIES && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /root/.cache/pip/*

# Set corect locale-related environment variables
ENV LANG="en_US.UTF-8" LANGUAGE="en_US:en" LC_ALL="en_US.UTF-8"

COPY ./bin/odood /usr/bin/odood

RUN odood deploy -v "$ODOO_VERSION" --supervisor=odood --log-to-stderr

WORKDIR /opt/odoo

EXPOSE 8069
EXPOSE 8071
EXPOSE 8072

VOLUME ["/opt/odoo/data", "/opt/odoo/backups"]

CMD ["/usr/bin/odood", "server", "run", "--config-from-env"]
