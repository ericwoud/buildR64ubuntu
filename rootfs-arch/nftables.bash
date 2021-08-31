#!/bin/bash
if [ $SETUP == "RT" ];then
  $schroot systemctl reenable nftables.service
else
  $schroot systemctl disable nftables.service
fi

