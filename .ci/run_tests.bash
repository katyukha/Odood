SCRIPT=$0;
SCRIPT_NAME=$(basename "$SCRIPT");
SCRIPT_DIR=$(dirname "$SCRIPT");
WORKDIR=$(pwd);

export INSTALL_LDC2_VERSION=1.33.0
export ODOOD_PYD_CONF=python39
export TEST_ODOO_TEMP=/opt/test-odood

mkdir -p "$TEST_ODOO_TEMP"

apt-get update
apt-get -yq upgrade
apt-get install --no-install-recommends -yq xz-utils sudo gpg libxml2 g++ wget ca-certificates libcurl4
apt-get install --no-install-recommends -yq libpq-dev python3-dev
apt-get install --no-install-recommends -yq build-essential
# Runtime deps needed for Odood to install and run Odoo (see nfpm.yaml for the full list)
apt-get install --no-install-recommends -yq \
    python3-virtualenv \
    libsass-dev libjpeg-dev libyaml-dev libfreetype6-dev zlib1g-dev \
    libxml2-dev libxslt-dev libbz2-dev libsasl2-dev libldap2-dev \
    libssl-dev libffi-dev liblzma-dev \
    fontconfig libmagic1
apt-get install --no-install-recommends -yq postgresql sudo

/etc/init.d/postgresql start
sudo -u postgres -H psql -c "CREATE USER odoo WITH SUPERUSER PASSWORD 'odoo';"

if [ ! -f /tmp/ldc2.tar.xz ]; then
    if ! wget -T 5 -O /tmp/ldc2.tar.xz https://github.com/ldc-developers/ldc/releases/download/v${INSTALL_LDC2_VERSION}/ldc2-${INSTALL_LDC2_VERSION}-linux-x86_64.tar.xz; then
        rm -f /tmp/ldc2.tar.xz;
    fi
    (cd /opt && tar -xf /tmp/ldc2.tar.xz)
    ln -s /opt/ldc2-${INSTALL_LDC2_VERSION}-linux-x86_64/bin/* /bin/
fi

echo "Test if python builds before running tests... Done";

(cd "${SCRIPT_DIR}" && \
    dub test -b unittest-cov -c unittest-silly --override-config="pyd/${ODOOD_PYD_CONF}" -- --threads=1 --verbose)
