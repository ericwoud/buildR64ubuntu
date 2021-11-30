#!/bin/bash

files="mt7615_cr4.bin mt7615_n9.bin mt7615_rom_patch.bin mt7622_n9.bin mt7622_rom_patch.bin mt7622pr2h.bin"
url="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek"

if [ ! -d "$rootfsdir/lib/firmware/mediatek" ]; then
  $sudo mkdir -p $rootfsdir/lib/firmware/mediatek
fi

for file in $files
do 
  $sudo wget --no-verbose -N $url"/"$file -P $rootfsdir/lib/firmware/mediatek
done

$sudo cp -r --remove-destination --dereference -v ./linux-$KERNELVERSION/firmware/ $rootfsdir/lib/

