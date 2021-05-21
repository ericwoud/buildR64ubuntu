#!/bin/bash
  $schroot systemctl disable hostapd.service
  find "custom/rootfs-$RELEASE/etc/hostapd" -name "*.conf"| while read service ; do
    service=$(basename $service)
    $schroot systemctl reenable "hostapd@"${service/.conf/} # enable all hostapd services
  done

