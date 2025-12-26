FROM ubuntu:24.04

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

COPY ./bin/binaries/ /binaries/

# Select and install the correct one based on target platform
RUN case ${TARGETARCH} in \
      "amd64")  cp /binaries/amd64/odood /usr/bin/odood && \
    cp /binaries/amd64/odood.bash /etc/bash_completion.d/odood.bash ;; \
      "arm64")  cp /binaries/arm64/odood  /usr/bin/odood && \
    cp /binaries/arm64/odood.bash /etc/bash_completion.d/odood.bash ;; \
      *)        echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    chmod +x /usr/bin/odood

RUN /usr/bin/odood deploy -v "$ODOO_VERSION" --supervisor=odood --log-to-stderr --db-password=odoo

WORKDIR /opt/odoo

EXPOSE 8069
EXPOSE 8071
EXPOSE 8072

VOLUME ["/opt/odoo/data", "/opt/odoo/backups"]

CMD ["/usr/bin/odood", "--config-from-env", "server", "run"]
