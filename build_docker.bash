#!/bin/bash


dub build --d-version OdoodInDocker && \
    dub build --d-version OdoodInDocker -c bash-autocomplete && \
    cp ./build/odood ./docker/bin/odood && \
    cp ./build/odood.bash ./docker/bin/odood.bash && \
    (cd ./docker && docker build -t tmp-odood:17 --build-arg ODOO_VERSION=17 --build-arg "ODOOD_DEPENDENCIES=$(cat ../.ci/deps/universal-deb.txt)" .)
