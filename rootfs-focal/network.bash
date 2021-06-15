#!/bin/bash

$sudo rm -rf $rootfsdir/etc/systemd/network
$sudo mv -vf $rootfsdir/etc/systemd/network-$SETUP $rootfsdir/etc/systemd/network
$sudo rm -rf $rootfsdir/etc/systemd/network-*

