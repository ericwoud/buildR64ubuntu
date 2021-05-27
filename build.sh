#!/bin/bash

LANG=C

GCC=""   # use standard ubuntu gcc version
#GCC="https://releases.linaro.org/components/toolchain/binaries/latest-7/aarch64-linux-gnu/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz"

#MAINLINE="http://kernel.ubuntu.com/~kernel-ppa/mainline/v5.4"
MAINLINE="http://kernel.ubuntu.com/~kernel-ppa/mainline/v5.12.2"

KERNELLOCALVERSION="-0"           # Is added to kernelversion by make for name of modules dir.

KERNELDTB="mt7622-bananapi-bpi-r64"
UBOOTDTB="mt7622-bananapi-bpi-r64"

ATFGIT="https://github.com/mtk-openwrt/arm-trusted-firmware.git"
ATFBRANCH="mt7622-bpir64"
#ATFBRANCH="mtksoc"  # Hangs at reboot

ATFDEVICE="sdmmc"
#ATFDEVICE="emmc"

#https://git.openwrt.org/?p=openwrt/openwrt.git;a=blob;f=package/boot/arm-trusted-firmware-mediatek/Makefile
ATFBUILDARGS="DDR3_FLYBY=1 LOG_LEVEL=40"

UBOOTGIT="https://github.com/u-boot/u-boot.git"
UBOOTBRANCH="v2021.01"
#UBOOTBRANCH="v2021.04" # Hangs
CONFIG_UBOOT_EXTRA="CONFIG_NET=n"

# https://github.com/bradfa/flashbench.git, running multiple times:
# sudo ./flashbench -a --count=64 --blocksize=1024 /dev/sda
# Shows me that times increase at alignment of 8k
SD_BLOCK_SIZE_KB=8                   # in kilo bytes
# When the SD card was brand new, formatted by the manufacturer, parted shows partition start at 4MiB
# 1      4,00MiB  29872MiB  29868MiB  primary  fat32        lba
SD_ERASE_SIZE_MB=4                   # in Mega bytes

RELEASE="focal"                      # Ubuntu version
NEEDEDPACKAGES="locales,hostapd,openssh-server,crda,resolvconf,iproute2,nftables,isc-dhcp-server"
EXTRAPACKAGES="vim,dbus,screen"      # Extra packages installed in rootfs, comma separated list, no spaces

LC="en_US.utf8"                      # Locale
TIMEZONE="Europe/Paris"              # Timezone
KEYBOARD="us"                        # Keyboard
ROOTPWD="admin"                      # Root password

MMC_BOOT_LEN=$(( 5 * 16 ))
SDMMC_BOOT="\
\x00\x00\x00\x00\x00\x00\x00\x00\x8b\xab\x63\xb8\x00\x00\x00\x00\
\x02\x00\xee\xff\xff\xff\x01\x00\x00\x00\xff\xff\xff\xff\x80\x00\
\x00\x00\xef\x00\x00\x00\x00\x04\x00\x00\x00\x04\x00\x00\x00\x00\
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x55\xaa\
"
EMMC_BOOT="\
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
\x02\x00\xee\xff\xff\xff\x01\x00\x00\x00\xff\xff\xe8\x00\x00\x00\
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x55\xaa\
"

if [ $ATFDEVICE = "emmc" ];then
  ubootdevnr=0
  mmc_boot=$EMMC_BOOT
else
  ubootdevnr=1
  mmc_boot=$SDMMC_BOOT
fi
rootpart="BPIR64"${ATFDEVICE^^}

function finish {
  if [ -v rootfsdir ] && [ ! -z $rootfsdir ]; then
    echo Running exit function to clean up...
    while [[ $(mountpoint $rootfsdir) =~  (is a mountpoint) ]]; do
      echo "Unmounting...DO NOT REMOVE!"
      $sudo umount -R $rootfsdir
      sleep 0.1
    done    
    $sudo rm -rf $rootfsdir
    echo -e "Done. You can remove the card now.\n"
  fi
}

function formatsd {
  readarray -t options < <(lsblk --nodeps -no name,serial,size | grep "^sd")
  PS3="Choose device to format: "
  select dev in "${options[@]}" "Quit" ; do
    if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then
      break
    else exit
    fi
  done    
  device="/dev/"${dev%% *}
  for PART in `df -k | awk '{ print $1 }' | grep "${device}"` ; do umount $PART; done
  $sudo parted -s "${device}" unit MiB print
  echo "\nAre you sure you want to format "$device"???" 
  read -p "Type <format> to format: " prompt
  if [[ $prompt == "format" ]]; then
    rootstart=$(( $SD_ERASE_SIZE_MB * 1024 ))
    [[ $rootstart -lt 4096 ]] && rootstart=4096
    $sudo dd of="${device}" if=/dev/zero bs=1024 count=$rootstart
    $sudo parted -s "${device}" mklabel gpt
    $sudo parted -s "${device}" unit kiB mkpart primary ext4 -- $rootstart 7634927
    $sudo parted -s "${device}" unit kiB mkpart primary ext2 -- 512 1024
    $sudo parted -s "${device}" unit kiB mkpart primary ext2 -- 1024 4096
    $sudo parted -s "${device}" name 1 root-${ATFDEVICE}
    $sudo parted -s "${device}" name 2 bl2
    $sudo parted -s "${device}" name 3 fip
    $sudo parted -s "${device}" unit kiB print
    $sudo partprobe "${device}"
    [[ $SD_BLOCK_SIZE_KB -lt 4 ]] && blksize=$SD_BLOCK_SIZE_KB || blksize=4
    stride=$(( $SD_BLOCK_SIZE_KB / $blksize ))
    stripe=$(( ($SD_ERASE_SIZE_MB * 1024) / $SD_BLOCK_SIZE_KB ))
    $sudo mkfs.ext4 -v -O ^has_journal -b $(( $blksize * 1024 ))  -L $rootpart \
      -E stride=$stride,stripe-width=$stripe "${device}1"
    $sudo sync
    $sudo lsblk -o name,mountpoint,label,size,uuid "${device}"
  fi
  (eject ${device}) > /dev/null 2>&1
}


# INIT VARIABLES
[ $USER = "root" ] && sudo="" || sudo="sudo -s"
[[ $# == 0 ]] && args="-brkta"|| args=$@
echo "build "$args
cd $(dirname $0)
while getopts ":rktabpmRKTSDBF" opt $args; do declare "${opt}=true" ; done
trap finish EXIT
shopt -s extglob
$sudo true

if  [ "$k" = true ] && [ "$m" = true ]; then
  echo "Kernel menuconfig only..."
else
  exec > >(tee build.log)
  exec 2> >(tee build-error.log)
fi

if [ "$(tr -d '\0' </proc/device-tree/model)" != "Bananapi BPI-R64" ]; then
  echo "Not running on Bananapi BPI-R64"
  makej="-j4" ##### Change: Find nr of cores....
  if [ "$S" = true ] && [ "$D" = true ]; then
    echo "Make SD-CARD!"
    formatsd
    exit
  fi
  if [ ! -z $(blkid -L $rootpart) ]; then
    rootfsdir=/mnt/bpirootfs
    $sudo umount $(blkid -L $rootpart)
    [ -d $rootfsdir ] || $sudo mkdir $rootfsdir
    $sudo mount --source LABEL=$rootpart --target $rootfsdir -t ext4 -o exec,dev,noatime,nodiratime
  else
    echo "Not inserted!"
    exit
  fi
else
  echo "Running on Bananapi BPI-R64"
  makej="-j2"
  rootfsdir="" ; r="" ; R=""
  gcc=""
fi

kernelversion=$(basename $MAINLINE)
[ ${kernelversion:0:1} == "v" ] && kernelversion="${kernelversion:1}"
schroot="$sudo LC_ALL=C LANGUAGE=C LANG=C chroot $rootfsdir"
kerneldir=$rootfsdir/usr/src/linux-headers-$kernelversion
echo OPTIONS: rootfs=$r kernel=$k tar=$t usb=$u apt=$a 
if [ "$K" = true ] ; then
  echo Removing kernelsource...
  $sudo rm -rf $kerneldir
fi
if [ "$R" = true ] ; then
  echo Removing rootfs...
  $sudo rm -rf $rootfsdir/!(usr)
  $sudo rm -rf $rootfsdir/usr/!(src)
fi
if [ "$T" = true ] ; then
  echo Removing .tar...
  rm -f rootfs.$RELEASE.tar.bz2 kernel.$kernelversion.tar.gz
fi
if [ "$B" = true ] ; then
  echo Removing boot...
  $sudo rm -rf $rootfsdir/usr/src/uboot
  $sudo rm -rf $rootfsdir/usr/src/atf
fi
if [ "$F" = true ] ; then
  echo Removing firmware...
  $sudo rm -rf $rootfsdir/lib/firmware/mediatek
fi
if [ "$a" = true ]; then
  $sudo apt-get install --yes git wget build-essential flex bison gcc-aarch64-linux-gnu \
                              u-boot-tools libncurses-dev libssl-dev
  if [ -z $rootfsdir ]; then
    $sudo apt-get install --yes bc ca-certificates  # install these when running on R64
  else
    $sudo apt-get install --yes gzip debootstrap qemu-user-static libc6:i386 
    gccname=$(basename $GCC)
    if [ ! -z $GCC ]; then
      wget -nv -N $GCC
      rm -rf gcc
      mkdir gcc
      tar -xf $gccname -C gcc  
    fi
  fi
fi
if [ -z $GCC ]; then
  gccpath=""
else
  [ -d gcc ] || mkdir gcc
  gccpath=$(realpath $(find gcc -wholename */bin/aarch64-linux-gnu-gcc))
  if [ ${#gccpath} -ge 21 ]; then gccpath=${gccpath:0:-21}
  else 
    echo Install the desired gcc first with option -a.
    exit
  fi
fi
[ ! -z $rootfsdir ] && crossc="CROSS_COMPILE="$gccpath"aarch64-linux-gnu-" || crossc=""
echo ROOTFSDIR: $rootfsdir
echo CROSSC: $crossc

### ROOTFS ###
if [ "$r" = true ]; then
  if [ ! -d "$rootfsdir/etc" ]; then
    if [ ! -f "rootfs.$RELEASE.tar.bz2" ]; then
      packages=$NEEDEDPACKAGES","$EXTRAPACKAGES
      [[ -f "rootfs-$RELEASE/etc/network/interfaces" ]] && packages="$packages,ifupdown"
      $sudo debootstrap --arch=arm64 --foreign --no-check-gpg --components=main,restricted,universe,multiverse \
        --include="$packages" $RELEASE $rootfsdir "http://ports.ubuntu.com/ubuntu-ports"
      $sudo cp /usr/bin/qemu-aarch64-static $rootfsdir/usr/bin/
      $schroot /debootstrap/debootstrap --second-stage
      if [ "$t" = true ]; then
        echo "Creating rootfs.tar..."
        $sudo tar -cjf rootfs.$RELEASE.tar.bz2 -C $rootfsdir .
        $sudo chown -R $USER:$USER rootfs.$RELEASE.tar.bz2
      fi
    else
      echo "Extracting rootfs.tar..."
      $sudo tar -xjf rootfs.$RELEASE.tar.bz2 -C $rootfsdir
    fi
  fi
  [ -z $($schroot locale -a | grep --ignore-case $LC) ] && $schroot locale-gen $LC
  $schroot update-locale LANGUAGE=$LC LC_ALL=$LC LANG=$LC
  $schroot ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
  $schroot sed -i 's/XKBLAYOUT=\"us\"/XKBLAYOUT=\"${KEYBOARD}\"/g' /etc/default/keyboard
  echo root:$ROOTPWD | $schroot chpasswd 
  $sudo cp -r --remove-destination -v rootfs-$RELEASE/. $rootfsdir
  for bp in $rootfsdir/*.bash ; do source $bp                                             ; $sudo rm -rf $bp ; done
  for bp in $rootfsdir/*.patch; do echo $bp ; $sudo patch -d $rootfsdir -p1 -N -r - < $bp ; $sudo rm -rf $bp ; done
  [[ -d "rootfs-$RELEASE/etc/systemd/network" ]] && $schroot systemctl reenable systemd-networkd.service
  find "rootfs-$RELEASE/etc/systemd/system" -name "*.service"| while read service ; do
    $schroot systemctl reenable $(basename $service)
  done
  $sudo mkdir -p $rootfsdir/root/buildR64ubuntu
  $sudo cp -rfv kernel-* $rootfsdir/root/buildR64ubuntu/
  $sudo cp -rfv rootfs-* $rootfsdir/root/buildR64ubuntu/
  $sudo cp -fv build.sh $rootfsdir/root/buildR64ubuntu/
fi

### BOOT ###
if [ "$b" = true ]; then
  $sudo mkdir -p $rootfsdir/usr/src/
  $sudo mkdir -p $rootfsdir/boot/
  if [ ! -d "$rootfsdir/usr/src/atf" ]; then
    $sudo git --no-pager clone --branch $ATFBRANCH --depth 1 $ATFGIT $rootfsdir/usr/src/atf
  fi
  if [ ! -d "$rootfsdir/usr/src/uboot" ]; then
    $sudo git --no-pager clone --branch $UBOOTBRANCH --depth 1 $UBOOTGIT $rootfsdir/usr/src/uboot
  fi
  $sudo cp -f $rootfsdir/usr/src/uboot/configs/mt7622_rfb_defconfig $rootfsdir/usr/src/uboot/configs/mt7622_my_bpi_defconfig
  $sudo cat <<EOT | $sudo tee -a $rootfsdir/usr/src/uboot/configs/mt7622_my_bpi_defconfig
CONFIG_DEFAULT_DEVICE_TREE="$UBOOTDTB"
CONFIG_DEFAULT_FDT_FILE="$UBOOTDTB"
CONFIG_CMD_EXT4=y
CONFIG_CMD_SETEXPR=y
CONFIG_HUSH_PARSER=y
CONFIG_EFI_PARTITION=y
CONFIG_USE_DEFAULT_ENV_FILE=y
CONFIG_DEFAULT_ENV_FILE="uEnv.txt"
$CONFIG_UBOOT_EXTRA
EOT
  $sudo echo "dev="${ubootdevnr} | $sudo tee    $rootfsdir/usr/src/uboot/uEnv.txt
  $sudo echo "bootargs=console=ttyS0,115200 root=PARTLABEL=root-${ATFDEVICE} rw rootwait ipp" | \
                                   $sudo tee -a $rootfsdir/usr/src/uboot/uEnv.txt
  $sudo cat <<'EOT' |              $sudo tee -a $rootfsdir/usr/src/uboot/uEnv.txt
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
  $sudo ARCH=arm64 $crossc make --directory=$rootfsdir/usr/src/uboot mt7622_my_bpi_defconfig all
  $sudo $crossc make --directory=$rootfsdir/usr/src/atf PLAT=mt7622 BL33=$rootfsdir/usr/src/uboot/u-boot.bin \
                     $ATFBUILDARGS BOOT_DEVICE=$ATFDEVICE all fip
  partdev=$(blkid -L $rootpart)
  if [ ! -z $partdev ];then
    device="/dev/"$(lsblk -no pkname $partdev)
    if [[ $? == 0 ]];then
      $sudo dd of="${device}" if=/dev/zero bs=512 count=1
      echo -en "${mmc_boot}" | sudo dd bs=1 of="${device}" seek=$(( 512 - $MMC_BOOT_LEN ))
      $sudo dd of="${device}2" if=$rootfsdir/usr/src/atf/build/mt7622/release/bl2.img bs=512 # remove bs=512 ???
      $sudo dd of="${device}3" if=$rootfsdir/usr/src/atf/build/mt7622/release/fip.bin bs=512 # remove bs=512 ???
    fi
  fi 
fi

### KERNEL ###
if [ "$k" = true ] ; then
  if [ ! -d "$rootfsdir/lib" ]; then
    echo "ERROR: Need to have rootfs installed first for propper directory structure!"
    exit
  fi
  [ -d $rootfsdir/usr/src ] || $sudo mkdir -p $rootfsdir/usr/src
  kerneldir=$(realpath $kerneldir)
  echo KERNELDIR: $kerneldir
  if [ ! -d "$kerneldir" ]; then
    if [ ! -f "kernel.$kernelversion.tar.gz" ]; then
      gitbranch=$(wget -nv -qO- $MAINLINE/HEADER.html | grep -m 1 git://)
      gitbranch=${gitbranch//&nbsp;/}
      gitbranch=(${gitbranch//<br>/})
      $sudo git --no-pager clone --branch ${gitbranch[1]} --depth 1 ${gitbranch[0]} $kerneldir
      $sudo rm -rf $kerneldir/.git
      sources=$(wget -nv -qO- $MAINLINE/SOURCES) ; readarray -t sources <<<"$sources"
      if [ ! -z "${sources[0]}" ]; then # has SOURCES file
        src=1
        while [ $src -lt ${#sources[@]} ]; do
          wget -nv -O /dev/stdout $MAINLINE"/"${sources[$src]} | $sudo patch -d $kerneldir -p1
          let src++
        done
      fi
      if [ "$t" = true ]; then
        echo "Creating kernel.tar..."
        tar -czf kernel.$kernelversion.tar.gz -C $kerneldir .
      fi
    else
      $sudo mkdir -p $kerneldir
      echo "Extracting kernel.tar..."
      $sudo tar -xzf kernel.$kernelversion.tar.gz -C $kerneldir
    fi
  fi  
  makeoptions="--directory="$kerneldir" LOCALVERSION="$KERNELLOCALVERSION" DEFAULT_HOSTNAME=R64UBUNTU ARCH=arm64 "$crossc" KCFLAGS=-w"
  outoftreeoptions=${makeoptions/--directory=/KDIR=}
  if [ "$p" = true ]; then
    $sudo make $makeoptions clean scripts modules_prepare
    exit
  fi
  $sudo cp --remove-destination -v kernel-$kernelversion/defconfig $kerneldir/arch/arm64/configs/r64ubuntu_defconfig
  $sudo make $makeoptions r64ubuntu_defconfig
  if [ "$m" = true ] ; then
    echo -e "\nSave altered config as '.config'.\n"
    read -p "Press <enter> to continue..." prompt
    $sudo make $makeoptions menuconfig
    $sudo make $makeoptions savedefconfig 
    format=$(realpath ./formatdefconfig.sh)
    (cd $kerneldir; $sudo "ARCH=arm64" $format)
    read -p "Type <save> to save configuration permanently: " prompt
    if [[ $prompt == "save" ]]; then
      cp --remove-destination -v $kerneldir/formatdef/defconfig kernel-$kernelversion/defconfig
    fi
    exit  
  fi  
  if [ ! -d "$rootfsdir/lib/firmware/mediatek" ]; then
    $sudo mkdir -p $rootfsdir/lib/firmware/mediatek
    $sudo wget --no-verbose --recursive --level=1 --no-parent --no-directories --convert-links -erobots=off \
     --directory-prefix=$rootfsdir/lib/firmware/mediatek --accept=.bin \
      https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/ 
  fi
  $sudo cp --remove-destination -v $kerneldir/.config $kerneldir/before.config
  $sudo mkdir -p $kerneldir/outoftree
  $sudo cp -r --remove-destination -v kernel-$kernelversion/. $kerneldir
  for bp in $kerneldir/*.bash ; do source $bp                                             ; $sudo rm -rf $bp ; done
  for bp in $kerneldir/*.patch; do echo $bp ; $sudo patch -d $kerneldir -p1 -N -r - < $bp ; $sudo rm -rf $bp ; done
  $sudo make $makeoptions KCONFIG_ALLCONFIG=.config allnoconfig # only add config entries added in patch.diff or bash.script
  diff -Naur  $kerneldir/before.config $kerneldir/.config >config-changes.diff
  $sudo rm -f $kerneldir/before.config
  $sudo make $makeoptions $makej scripts modules_prepare
  kernelrelease=$($sudo make -s $makeoptions kernelrelease)
  $sudo make $makeoptions $makej UIMAGE_LOADADDR=0x40008000 Image dtbs modules # Remove UIMAGE_LOADADDR= ???
  [[ $? != 0 ]] && exit  
  $sudo mkimage -A arm64 -O linux -T kernel -C none -a 40080000 -e 40080000 -n "Linux Kernel $kernelrelease" \
                -d $kerneldir/arch/arm64/boot/Image $kerneldir/uImage
  $sudo mkdir -p $rootfsdir/boot/
#  $sudo cp -af $kerneldir/arch/arm64/boot/dts/mediatek/*.dtb $rootfsdir/boot/
  $sudo cp -af $kerneldir/arch/arm64/boot/dts/mediatek/$KERNELDTB.dtb $rootfsdir/boot/$kernelrelease.dtb
  $sudo cp -af $kerneldir/uImage $rootfsdir/boot/$kernelrelease.uImage
  $sudo echo -e "image=boot/$kernelrelease.uImage\ndtb=boot/$kernelrelease.dtb" | \
             $sudo tee    $rootfsdir/boot/uEnv.txt
  $sudo make $makeoptions modules_install INSTALL_MOD_PATH="../../.."
  if [ $kerneldir/outoftree/* != "$kerneldir/outoftree/*" ]; then
    $sudo mkdir -p $rootfsdir/lib/modules/$kernelrelease/extra
    for module in $kerneldir/outoftree/*
    do 
      (cd $module; $sudo make $outoftreeoptions) 
      [[ $? == 0 ]] && $sudo cp -fv $module/*.ko $rootfsdir/lib/modules/$kernelrelease/extra
    done
  fi
  $sudo depmod -ab $rootfsdir/. $kernelrelease
  $sudo ln -v --force --symbolic --relative --no-dereference $kerneldir $rootfsdir/lib/modules/$kernelrelease/build
  $sudo ln -v --force --symbolic --relative --no-dereference $kerneldir $rootfsdir/lib/modules/$kernelrelease/source
fi

exit

./build.sh: line 142: warning: command substitution: ignored null byte in input

