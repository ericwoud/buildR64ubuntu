#!/bin/bash

mkipatchgit="https://git.openwrt.org/?p=openwrt/openwrt.git;a=blob_plain;f=tools/mkimage/patches"

mkipatches="080-mtk_image-add-support-for-booting-ARM64-images.patch \
            081-mtk_image-add-an-option-to-set-device-header-offset.patch"

# commit for uboot mkimage patches, that are meant for the 2021.01 version:
mkihb="f36990eae77c3a22842a2c418378c5dd40dec366"

for filename in $mkipatches; do
  wget -nv -O /dev/stdout $mkipatchgit/$filename";hb="$mkihb | $sudo patch -d $src/uboot-$UBOOTBRANCH -p1
done


