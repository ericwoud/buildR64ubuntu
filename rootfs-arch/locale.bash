#!/bin/bash

$schroot ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime

$schroot systemctl reenable systemd-timesyncd.service

