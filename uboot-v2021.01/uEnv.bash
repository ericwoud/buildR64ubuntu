#!/bin/bash

$sudo echo "dev="${ubootdevnr} | $sudo tee    $src/uboot/uEnv.txt
$sudo echo "bootargs=$KERNELBOOTARGS root=PARTLABEL=root-${ATFDEVICE}" | \
                                 $sudo tee -a $src/uboot/uEnv.txt
$sudo cat <<'EOT' |              $sudo tee -a $src/uboot/uEnv.txt
kaddr=0x44000000
dtaddr=0x47000000
image=boot/uImage
dtb=boot/dtb
uenv=boot/uEnv.txt
bootdelay=-2
loadenvfile=if ext4load mmc ${dev}: ${kaddr} ${uenv};then env import -t ${kaddr} ${filesize};fi
loadimage=ext4load mmc ${dev}: ${kaddr} ${image}
loaddtb=ext4load mmc ${dev}: ${dtaddr} ${dtb}
bootkernel=bootm ${kaddr} - ${dtaddr}
bootcmd=run loadenvfile; run loadimage loaddtb bootkernel
EOT

