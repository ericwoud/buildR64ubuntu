#!/bin/bash

$sudo rm -rf $rootfsdir/etc/systemd/network
$sudo mv -vf $rootfsdir/etc/systemd/network-$SETUP $rootfsdir/etc/systemd/network
$sudo rm -rf $rootfsdir/etc/systemd/network-*

$schroot systemctl reenable systemd-resolved.service

$schroot systemctl reenable hostapd.service

