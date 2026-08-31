FROM ubuntu:24.04 AS base

ARG ODOO_VERSION
ARG ODOOD_DEPENDENCIES
ARG TARGETARCH

# UID/GID 999 is the top of the system range (Postgres/MySQL/Redis use it too)
# and is free on the base image, so the 'odoo' system user gets a fixed,
# predictable ID.
ARG ODOOD_SERVER_USER_UID=999
ARG ODOOD_SERVER_USER_GID=999

# Security fix (CVE-2026-64564): linux kernel userspace headers are pinned to
# a version >= 6.8.0-136.136 (the fix version). 6.8.0-138.138 satisfies this.
RUN apt-get update -qq && \
    apt-get install -qqq -y --no-install-recommends --auto-remove \
        locales \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        xfonts-75dpi xfonts-base libx11-6 libxcb1 libxext6 libxrender1 libsqlite3-dev\
        linux-libc-dev=6.8.0-138.138 \
        build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
        libffi-dev liblzma-dev libncursesw5-dev tk-dev uuid-dev libgdbm-dev xz-utils \
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

# Build and use Python 3.12.14 for the Odoo virtualenv.
# The base image (ubuntu:24.04) ships Python 3.12.3, which Odood would otherwise
# reuse as-is (PyInstallType.System). Passing --py-version forces Odood to build
# CPython 3.12.14 from source (PyInstallType.Build), so the shipped image runs
# the pinned patch release instead of the distro's Python.
RUN /usr/bin/odood deploy -v "$ODOO_VERSION" --py-version=3.12.14 --supervisor=odood --log-to-stderr --db-password=odoo \
        --server-user-uid="$ODOOD_SERVER_USER_UID" --server-user-gid="$ODOOD_SERVER_USER_GID" && \
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
