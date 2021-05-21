#!/bin/bash
$schroot systemctl reenable isc-dhcp-server.service
$sudo cp --no-clobber $rootfsdir/etc/dhcp/dhcpd.conf $rootfsdir/etc/dhcp/dhcpd-orig.conf
$sudo cp              $rootfsdir/etc/dhcp/dhcpd-orig.conf $rootfsdir/etc/dhcp/dhcpd.conf
$sudo cat <<EOT | $sudo tee -a $rootfsdir/etc/dhcp/dhcpd.conf

subnet 192.168.5.0 netmask 255.255.255.0 {
 range 192.168.5.150 192.168.5.200;
 option routers 192.168.5.1;
 option domain-name-servers 8.8.8.8;
 option domain-name "mydomain.example";
}
subnet 192.168.6.0 netmask 255.255.255.0 {
 range 192.168.6.150 192.168.6.200;
 option routers 192.168.6.1;
 option domain-name-servers 8.8.8.8;
 option domain-name "mydomain.guest";
}
EOT

