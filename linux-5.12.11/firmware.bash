#!/bin/bash

files="mt7622_n9.bin mt7622_rom_patch.bin"
url="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek"

if [ ! -d "$rootfsdir/lib/firmware/mediatek" ]; then
  $sudo mkdir -p $rootfsdir/lib/firmware/mediatek
fi

for file in $files
do 
  $sudo wget --no-verbose -N $url"/"$file -P $rootfsdir/lib/firmware/mediatek
done

$sudo cp -r --remove-destination --dereference -v rootfs-$RELEASE/lib/firmware/ $rootfsdir/lib/

