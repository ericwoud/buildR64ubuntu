#!/bin/bash

nr=16 # Make sure there are 16 available mac addresses: nr=16/32/64
first=AA:BB:CC
mac5=$first:$(printf %02X $(($RANDOM%256))):$(  printf %02X $(($RANDOM%256)))
mac=$mac5:$(printf %02X $(($(($RANDOM%256))&-$nr)))
echo $mac $nr | $sudo tee $rootfsdir/etc/mac.eth0.txt
mac=$mac5
while [ "$mac" == "$mac5" ]; do # make sure second mac is different
  mac=$first:$(printf %02X $(($RANDOM%256))):$(printf %02X $(($RANDOM%256)))
done
mac=$mac:$(printf %02X $(($RANDOM%256)) )
echo $mac | $sudo tee $rootfsdir/etc/mac.eth1.txt

