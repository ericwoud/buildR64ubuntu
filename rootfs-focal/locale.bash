#!/bin/bash

[ -z $($schroot locale -a | grep --ignore-case $LC) ] && $schroot locale-gen $LC
$schroot update-locale LANGUAGE=$LC LC_ALL=$LC LANG=$LC
$schroot ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime

