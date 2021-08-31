#!/bin/bash

mkipatchgit="https://git.openwrt.org/?p=openwrt/openwrt.git;a=blob_plain;f=tools/mkimage/patches"

mkipatches="080-mtk_image-add-support-for-booting-ARM64-images.patch \
            081-mtk_image-add-an-option-to-set-device-header-offset.patch"

# commit for uboot mkimage patches, that are meant for the 2021.01 version:
mkihb="f36990eae77c3a22842a2c418378c5dd40dec366"

for filename in $mkipatches; do
  $sudo wget --no-verbose -nc $mkipatchgit/$filename";hb="$mkihb -O $src/uboot-$UBOOTBRANCH/$filename
  [ ! -f "$src/uboot-$UBOOTBRANCH/$filename" ] && exit
  $sudo patch -d $src/uboot-$UBOOTBRANCH -p1 -N --input=$src/uboot-$UBOOTBRANCH/$filename -r -
  [[ $? == 2 ]] && exit
done


