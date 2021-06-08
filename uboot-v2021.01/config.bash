#!/bin/bash

$sudo cp -f $src/uboot-$UBOOTBRANCH/configs/mt7622_rfb_defconfig \
            $src/uboot-$UBOOTBRANCH/configs/mt7622_my_bpi_defconfig
$sudo cat <<EOT | $sudo tee -a \
            $src/uboot-$UBOOTBRANCH/configs/mt7622_my_bpi_defconfig
CONFIG_DEFAULT_DEVICE_TREE="$UBOOTDTB"
CONFIG_DEFAULT_FDT_FILE="$UBOOTDTB"
CONFIG_CMD_EXT4=y
CONFIG_CMD_SETEXPR=y
CONFIG_HUSH_PARSER=y
CONFIG_EFI_PARTITION=y
CONFIG_USE_DEFAULT_ENV_FILE=y
CONFIG_DEFAULT_ENV_FILE="uEnv.txt"

CONFIG_NET=n
CONFIG_DM_GPIO=y
CONFIG_DM_RESET=y
EOT

