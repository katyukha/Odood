#!/bin/bash


dub build --d-version OdoodInDocker && \
    dub build --d-version OdoodInDocker -c bash-autocomplete && \
    mkdir -p "./docker/bin/$(dpkg --print-architecture)/" && \
    cp ./build/odood "./docker/bin/$(dpkg --print-architecture)/odood" && \
    cp ./build/odood.bash "./docker/bin/$(dpkg --print-architecture)/odood.bash" && \
    (cd ./docker && docker build -t tmp-odood:18 --build-arg ODOO_VERSION=18 --build-arg "ODOOD_DEPENDENCIES=$(cd .. && .ci/print_deps.d)" .)
