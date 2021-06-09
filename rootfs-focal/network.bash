#!/bin/bash

$sudo rm -rf $rootfsdir/etc/systemd/network
$sudo cp -r $rootfsdir/etc/systemd/network-$SETUP $rootfsdir/etc/systemd/network

