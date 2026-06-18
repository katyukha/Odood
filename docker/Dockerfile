FROM ubuntu:24.04 AS base

ARG ODOO_VERSION
ARG ODOOD_DEPENDENCIES
ARG TARGETARCH

RUN apt-get update -qq && \
    apt-get install -qqq -y --no-install-recommends --auto-remove \
        locales \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        xfonts-75dpi xfonts-base libx11-6 libxcb1 libxext6 libxrender1 libsqlite3-dev\
        tzdata && \
    locale-gen en_US.UTF-8 && \
    locale-gen en_GB.UTF-8 && \
    update-locale LANG="en_US.UTF-8" && update-locale LANGUAGE="en_US:en" \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
            apt-key add - && \
	apt-get update -qq && \
    apt-get install -qqq -y --no-install-recommends --auto-remove $ODOOD_DEPENDENCIES && \
    wget --quiet -O /tmp/wkhtmltopdf.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_$(dpkg --print-architecture).deb && \
        dpkg -i /tmp/wkhtmltopdf.deb && \
        rm -f /tmp/wkhtmltopdf.deb && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /root/.cache/pip/*

# Set corect locale-related environment variables
ENV LANG="en_US.UTF-8" LANGUAGE="en_US:en" LC_ALL="en_US.UTF-8"

COPY ./bin/${TARGETARCH}/odood /usr/bin/odood
COPY ./bin/${TARGETARCH}/odood.bash /etc/bash_completion.d/odood.bash

RUN /usr/bin/odood deploy -v "$ODOO_VERSION" --supervisor=odood --log-to-stderr --db-password=odoo \
        --server-user-uid=1000 --server-user-gid=1000 && \
    rm -rf /root/.cache/pip/*

WORKDIR /opt/odoo

EXPOSE 8069
EXPOSE 8071
EXPOSE 8072

VOLUME ["/opt/odoo/data", "/opt/odoo/backups"]

STOPSIGNAL SIGINT

CMD ["/usr/bin/odood", "--config-from-env", "server", "run", "--wait-pg"]


# Production image (default target): adds a HEALTHCHECK for orchestrators.
FROM base AS production

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD odood server healthcheck -t 9


# CI image: no HEALTHCHECK (disposable test runner), with the dev/lint/test
# toolbelt (pre-commit, eslint, flake8, pylint-odoo, coverage, ...) pre-installed.
FROM base AS ci

RUN /usr/bin/odood venv install-dev-tools && \
    rm -rf /root/.cache
