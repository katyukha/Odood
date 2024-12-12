#!/bin/bash


dub build --d-version OdoodInDocker;
cp ./build/odood ./docker/bin/odood;
(cd ./docker && docker build -t tmp-odood:17 --build-arg ODOO_VERSION=17 --build-arg "ODOOD_DEPENDENCIES=$(cat ../.ci/deps/universal-deb.txt)" .)
