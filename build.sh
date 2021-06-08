#!/bin/bash

export LANG=C

GCC=""   # use standard ubuntu gcc version
#GCC="https://releases.linaro.org/components/toolchain/binaries/latest-7/aarch64-linux-gnu/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz"

SRC=""                 # Installs source in /usr/src of sd-card/image
#SRC="./src/"          # Installs source in same folder as build.sh

#KERNEL="http://kernel.ubuntu.com/~kernel-ppa/mainline"
KERNEL="https://github.com/torvalds/linux.git"

KERNELVERSION="v5.12"        # Kernel files in folder named 'kernel-5.12'

KERNELLOCALVERSION="-0"      # Is added to kernelversion by make for name of modules dir.

KERNELBOOTARGS="console=ttyS0,115200 rw rootwait ipp"

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

# Uncomment if you do not want to use a SD card, but a loop-device instead.
#USE_LOOPDEV="true"          # Remove SD card, because of same label

IMAGE_FILE="./my-bpir64.img"

# https://github.com/bradfa/flashbench.git, running multiple times:
# sudo ./flashbench -a --count=64 --blocksize=1024 /dev/sda
# Shows me that times increase at alignment of 8k
SD_BLOCK_SIZE_KB=8                   # in kilo bytes
# When the SD card was brand new, formatted by the manufacturer, parted shows partition start at 4MiB
# 1      4,00MiB  29872MiB  29868MiB  primary  fat32        lba
SD_ERASE_SIZE_MB=4                   # in Mega bytes

ROOTFS_EXT4_OPTIONS=""
#ROOTFS_EXT4_OPTIONS="-O ^has_journal"  # No journal is faster, but you can get errors after powerloss
ROOTFS_LABEL="BPI-ROOT"

IMAGE_SIZE_MB=7400                # Must be multiple of SD_ERASE_SIZE_MB !
#IMAGE_SIZE_MB=""                 # Fill until end of card. Cannot use with image creaion.
BL2_START_KB=512
BL2_SIZE_KB=512
MINIMAL_SIZE_FIP_MB=3

DEBOOTSTR_SOURCE="http://ports.ubuntu.com/ubuntu-ports" # Ubuntu
DEBOOTSTR_COMPNS="main,restricted,universe,multiverse"  # Ubuntu
RELEASE="focal"                                         # Ubuntu version
#DEBOOTSTR_SOURCE="http://ftp.debian.org/debian/"       # Debian
#DEBOOTSTR_COMPNS="main,contrib,non-free"               # Debian
#RELEASE="buster"                                       # Debian version

NEEDEDPACKAGES="locales,hostapd,openssh-server,crda,resolvconf,iproute2,nftables,isc-dhcp-server"
EXTRAPACKAGES="vim,dbus,screen"      # Extra packages installed in rootfs, comma separated list, no spaces

LC="en_US.utf8"                      # Locale
TIMEZONE="Europe/Paris"              # Timezone
KEYBOARD="us"                        # Keyboard
ROOTPWD="admin"                      # Root password

function unmountrootfs {
  if [ -v rootfsdir ] && [ ! -z $rootfsdir ]; then
    $sudo sync
    echo Running exit function to clean up...
    $sudo sync
    echo $(mountpoint $rootfsdir)
    while [[ $(mountpoint $rootfsdir) =~  (is a mountpoint) ]]; do
      echo "Unmounting...DO NOT REMOVE!"
      $sudo umount -R $rootfsdir
      sleep 0.1
    done    
    $sudo rm -rf $rootfsdir
    echo -e "Done. You can remove the card now.\n"
  fi
  unset rootfsdir
}

function attachloopdev {
  local -n loopdevlocal=loopdev
  loop_dirty=$($sudo udisksctl loop-setup -f $IMAGE_FILE)
  loop_dirty=${loop_dirty#*/dev/}
  loopdevlocal="/dev/"${loop_dirty/./}
}

function detachloopdev {
  local -n loopdevlocal=loopdev
  if [ ! -z $loopdevlocal ]; then
    $sudo udisksctl loop-delete --block-device $loopdevlocal
    loopdevlocal=""
  fi
}

function finish {
  unmountrootfs
  detachloopdev
}

function formatsd {
  if [ "$USE_LOOPDEV" == true ]; then 
    if [ -f "$IMAGE_FILE" ]; then    
      echo -e "\n$IMAGE_FILE exists. Are you sure you want to format???" 
      read -p "Type <format> to format: " prompt
      [[ $prompt != "format" ]] && exit
    fi  
    dd if=/dev/zero of=$IMAGE_FILE bs=1M count=$IMAGE_SIZE_MB status=progress 
    attachloopdev
    device=$loopdev
    IMAGE_SIZE_MB=""
  else            
    readarray -t options < <(lsblk --nodeps -no name,serial,size \
                     | grep $formatpattern | grep -v 'boot0\|boot1\|boot2')
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
    echo -e "\nAre you sure you want to format "$device"???" 
    read -p "Type <format> to format: " prompt
    [[ $prompt != "format" ]] && exit
  fi
  minimalrootstart=$(( $BL2_START_KB + $BL2_SIZE_KB + ($MINIMAL_SIZE_FIP_MB * 1024) ))
  rootstart=0
  while [[ $rootstart -lt $minimalrootstart ]]; do 
    rootstart=$(( $rootstart + ($SD_ERASE_SIZE_MB * 1024) ))
  done
  [ -z  $IMAGE_SIZE_MB ] && rootend="100%" || rootend=$(( $IMAGE_SIZE_MB * 1024 ))
  $sudo dd of="${device}" if=/dev/zero bs=1024 count=$rootstart
  $sudo parted -s -- "${device}" unit kiB \
    mklabel gpt \
    mkpart primary ext4 $rootstart                                       $rootend \
    mkpart primary ext2 $(( $BL2_START_KB + $BL2_SIZE_KB ))            $rootstart \
    mkpart primary ext2 $BL2_START_KB         $(( $BL2_START_KB + $BL2_SIZE_KB )) \
    name 1 root-bpir64-${ATFDEVICE} \
    name 2 fip \
    name 3 bl2 \
    print
  $sudo partprobe "${device}"
  [[ $SD_BLOCK_SIZE_KB -lt 4 ]] && blksize=$SD_BLOCK_SIZE_KB || blksize=4
  stride=$(( $SD_BLOCK_SIZE_KB / $blksize ))
  stripe=$(( ($SD_ERASE_SIZE_MB * 1024) / $SD_BLOCK_SIZE_KB ))
  lsblkdev=""
  while [ -z $lsblkdev ]; do
    lsblkdev=($(lsblk -prno name,pkname,partlabel | grep root-bpir64-${ATFDEVICE}))
    sleep 0.1
  done
  mountdev=${lsblkdev[0]}
  echo test $mountdev
  $sudo mkfs.ext4 -v $ROOTFS_EXT4_OPTIONS -b $(( $blksize * 1024 ))  -L $ROOTFS_LABEL \
                  -E stride=$stride,stripe-width=$stripe "${mountdev}"
  $sudo sync
  $sudo lsblk -o name,mountpoint,label,size,uuid "${device}"
}

# INIT VARIABLES
[ $USER = "root" ] && sudo="" || sudo="sudo -s"
[[ $# == 0 ]] && args="-brkta"|| args=$@
echo "build "$args
cd $(dirname $0)
while getopts ":rktabpmcRKTSDBF" opt $args; do declare "${opt}=true" ; done
trap finish EXIT
shopt -s extglob
$sudo true

if  [ "$k" = true ] && [ "$m" = true ]; then
  echo "Kernel menuconfig only..."
else
  exec > >(tee -i build.log) # Needs -i for propper CTRL-C catch
  exec 2> >(tee build-error.log) # No -i, work better with git clone? fixed with nopager?
fi

echo "Target device="$ATFDEVICE
if [ "$(tr -d '\0' 2>/dev/null </proc/device-tree/model)" != "Bananapi BPI-R64" ]; then
  echo "Not running on Bananapi BPI-R64"
  formatpattern="^sd"
  bpir64="false"
else
  echo "Running on Bananapi BPI-R64"
  formatpattern="^mmc"
  GCC=""
  bpir64="true"
fi
if [ $ATFDEVICE = "emmc" ];then
  ubootdevnr=0
else
  ubootdevnr=1
fi
loopdev=""
# lsblk -prno name,partlabel | grep root-bpir64-sdmmc
lsblkdev=($(lsblk -prno name,pkname,partlabel | grep root-bpir64-${ATFDEVICE}))
if [ ! -z $lsblkdev ]; then
  mountdev=${lsblkdev[0]}
  device=${lsblkdev[1]}
else
  mountdev=""
  device=""
fi
if [ "$USE_LOOPDEV" == true ]; then
  if [ ! -z $mountdev ]; then
    echo "SD-Card is also inserted, cannot use loop-device!"
    exit
  fi
  if [ "$S" = true ] && [ "$D" = true ]; then formatsd; exit; fi
  attachloopdev
  rootfsdir=/mnt/bpirootfs
  device=$loopdev
  mountdev=${loopdev}"p1"
else
  if [ "$S" = true ] && [ "$D" = true ]; then formatsd; exit; fi
  if [ -z $mountdev ]; then
    echo "Not inserted! (Maybe not matching the target device on the card)"
    exit
  fi
  rootdev=$(lsblk -pilno name,type,mountpoint | grep -G 'part /$')
  rootdev=${rootdev%% *}
  if [ $rootdev == $mountdev ];then
    rootfsdir="" ; r="" ; R=""      # Protect root when running from it!
  else
    rootfsdir=/mnt/bpirootfs
    $sudo umount $mountdev
  fi
fi

if [ ! -z $rootfsdir ]; then
  [ -d $rootfsdir ] || $sudo mkdir $rootfsdir
  $sudo mount --source $mountdev --target $rootfsdir -t ext4 \
              -o exec,dev,noatime,nodiratime
fi

[ ${KERNELVERSION:0:1} == "v" ] && kernelversion="${KERNELVERSION:1}" || kernelversion=$KERNELVERSION
schroot="$sudo LC_ALL=C LANGUAGE=C LANG=C chroot $rootfsdir"
[ -z $SRC ] && src=$rootfsdir/usr/src || src=$SRC
[ -z $rootfsdir ] && src="/usr/src"
kerneldir=$src/linux-headers-$kernelversion
echo OPTIONS: rootfs=$r boot=$b kernel=$k tar=$t apt=$a 
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
  $sudo rm -rf $src/uboot-$UBOOTBRANCH
  $sudo rm -rf $src/atf-$ATFBRANCH
fi
if [ "$F" = true ] ; then
  echo Removing firmware...
  $sudo rm -rf $rootfsdir/lib/firmware/mediatek
fi
if [ "$a" = true ]; then
  $sudo apt-get install --yes git wget build-essential flex bison gcc-aarch64-linux-gnu \
                              u-boot-tools libncurses-dev libssl-dev zerofree symlinks
  if [ $bpir64 == "true" ]; then
    $sudo apt-get install --yes bc ca-certificates mmc-utils # install these when running on R64
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
[ $bpir64 != "true" ] && crossc="CROSS_COMPILE="$gccpath"aarch64-linux-gnu-" || crossc=""
makej=-j$(grep ^processor /proc/cpuinfo  | wc -l)
echo "Rootfsdir="$rootfsdir
echo "Crossc="$crossc
echo "Device="$device
echo "Mountdev="$mountdev
echo "Makej="$makej

### ROOTFS ###
if [ "$r" = true ]; then
  if [ ! -d "$rootfsdir/etc" ]; then
    if [ -d "$rootfsdir/lib" ]; then
       echo -e "Only fake /lib/ on rootfs for kernel only. Empty rootfs before installing.\n Use ./build.sh -BRR"
       exit
    fi
    if [ ! -f "rootfs.$RELEASE.tar.bz2" ]; then
      packages=$NEEDEDPACKAGES","$EXTRAPACKAGES
      [[ -f "rootfs-$RELEASE/etc/network/interfaces" ]] && packages="$packages,ifupdown"
      $sudo debootstrap --arch=arm64 --foreign --no-check-gpg --components=$DEBOOTSTR_COMPNS \
        --include="$packages" $RELEASE $rootfsdir $DEBOOTSTR_SOURCE
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
  echo root:$ROOTPWD | $schroot chpasswd 
  symlinks -cr .
  $sudo cp -r --remove-destination --dereference -v rootfs-$RELEASE/. $rootfsdir
  for bp in $rootfsdir/*.bash ; do source $bp                                             ; $sudo rm -rf $bp ; done
  for bp in $rootfsdir/*.patch; do echo $bp ; $sudo patch -d $rootfsdir -p1 -N -r - < $bp ; $sudo rm -rf $bp ; done
  [[ -d "rootfs-$RELEASE/etc/systemd/network" ]] && $schroot systemctl reenable systemd-networkd.service
  find -L "rootfs-$RELEASE/etc/systemd/system" -name "*.service"| while read service ; do
    $schroot systemctl reenable $(basename $service)
  done
  $sudo mkdir -p $rootfsdir/root/buildR64ubuntu
  $sudo cp -rfv --no-dereference kernel-* $rootfsdir/root/buildR64ubuntu/
  $sudo cp -rfv --no-dereference rootfs-* $rootfsdir/root/buildR64ubuntu/
  $sudo cp -rfv --no-dereference uboot-*  $rootfsdir/root/buildR64ubuntu/
  $sudo cp -rfv --no-dereference atf-*    $rootfsdir/root/buildR64ubuntu/
  $sudo cp -fv build.sh $rootfsdir/root/buildR64ubuntu/
fi

### BOOT ###
if [ "$b" = true ]; then
  $sudo mkdir -p $src/
  $sudo mkdir -p $rootfsdir/boot/
  if [ ! -d "$src/atf-$ATFBRANCH" ]; then
    $sudo git --no-pager clone --branch $ATFBRANCH --depth 1 $ATFGIT $src/atf-$ATFBRANCH
  fi
  if [ ! -d "$src/uboot-$UBOOTBRANCH" ]; then
    $sudo git --no-pager clone --branch $UBOOTBRANCH --depth 1 $UBOOTGIT $src/uboot-$UBOOTBRANCH
  fi
  for bp in ./atf-$ATFBRANCH/*.bash ;     do source $bp ; done
  for bp in ./uboot-$UBOOTBRANCH/*.bash ; do source $bp ; done
  for bp in ./atf-$ATFBRANCH/*.patch;     do echo $bp ; $sudo patch -d $src/atf-$ATFBRANCH      -p1 -N -r - < $bp ; done
  for bp in ./uboot-$UBOOTBRANCH/*.patch; do echo $bp ; $sudo patch -d  $src/uboot-$UBOOTBRANCH -p1 -N -r - < $bp ; done
  ARCH=arm64 $sudo make $makej $crossc --directory=$src/uboot-$UBOOTBRANCH mt7622_my_bpi_defconfig all
             $sudo make $makej $crossc --directory=$src/atf-$ATFBRANCH PLAT=mt7622 \
             BL33=$src/uboot-$UBOOTBRANCH/u-boot.bin $ATFBUILDARGS USE_MKIMAGE=1 \
             MKIMAGE=$src/uboot-$UBOOTBRANCH/tools/mkimage BOOT_DEVICE=$ATFDEVICE all fip #USE_MKIMAGE=1
  make -j1 --directory=./tools/ clean all # -j1 so first clean then all
  ./tools/echo-bpir64-mbr $ATFDEVICE $(( $BL2_START_KB * 2 )) $(( $BL2_SIZE_KB * 2 )) \
                   | sudo dd of="${device}"
  $sudo dd of="${mountdev::-1}2" if=/dev/zero 2>/dev/null
  $sudo dd of="${mountdev::-1}2" if=$src/atf-$ATFBRANCH/build/mt7622/release/fip.bin
  $sudo dd of="${mountdev::-1}3" if=/dev/zero 2>/dev/null
  $sudo dd of="${mountdev::-1}3" if=$src/atf-$ATFBRANCH/build/mt7622/release/bl2.img
  if [ -b ${device}"boot0" ] && [ $bpir64 == "true" ]; then
    force_ro="/sys/block/"${device/"/dev/"/}"boot0/force_ro"
    echo FORCE=$force_ro
    echo 0 >$force_ro
    $sudo dd of=${device}"boot0" if=/dev/zero 2>/dev/null
    $sudo dd of=${device}"boot0" if=$src/atf-$ATFBRANCH/build/mt7622/release/bl2.img
    echo 1 >$force_ro
    $sudo mmc bootpart enable 1 1 ${device}
  fi
fi

### KERNEL ###
if [ "$k" = true ] ; then
  if [ ! -d "$rootfsdir/lib" ]; then
    $sudo mkdir -p $rootfsdir/lib/modules
    echo -e "Creating fake rootfs to install kernel modules only.\nBuild rootfs first if you need one."
  fi
  [ -d $src ] || $sudo mkdir -p $src
  kerneldir=$(realpath $kerneldir)
  echo "Kerneldir="$kerneldir
  if [ ! -d "$kerneldir" ]; then
    if [ ! -f "kernel.$kernelversion.tar.gz" ]; then
      if [ ${KERNEL: -4} == ".git" ]; then
        $sudo git --no-pager clone --branch $KERNELVERSION --depth 1 $KERNEL $kerneldir
      else
        gitbranch=$(wget -nv -qO- $KERNEL/$KERNELVERSION/HEADER.html | grep -m 1 git://)
        gitbranch=${gitbranch//&nbsp;/}
        gitbranch=(${gitbranch//<br>/})
        $sudo git --no-pager clone --branch ${gitbranch[1]} --depth 1 ${gitbranch[0]} $kerneldir
        $sudo rm -rf $kerneldir/.git
        sources=$(wget -nv -qO- $KERNEL/$KERNELVERSION/SOURCES) ; readarray -t sources <<<"$sources"
        if [ ! -z "${sources[0]}" ]; then # has SOURCES file
          src=1
          while [ $src -lt ${#sources[@]} ]; do
            wget -nv -O /dev/stdout $KERNEL/$KERNELVERSION/${sources[$src]} | $sudo patch -d $kerneldir -p1
            let src++
          done
        fi
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
    $sudo make $makeoptions distclean scripts modules_prepare
    (cd src/uboot-$UBOOTBRANCH; $sudo make distclean)
    (cd src/atf-$ATFBRANCH;     $sudo make distclean)
    exit
  fi
  $sudo cp --remove-destination --dereference -v kernel-$kernelversion/defconfig $kerneldir/arch/arm64/configs/r64ubuntu_defconfig
  $sudo make $makeoptions r64ubuntu_defconfig
  if [ "$m" = true ] ; then
    echo -e "\nSave altered config as '.config'.\n"
    read -p "Press <enter> to continue..." prompt
    $sudo make $makeoptions menuconfig
    $sudo make $makeoptions savedefconfig 
    format=$(realpath ./tools/formatdefconfig.sh)
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
  symlinks -cr .
  $sudo cp -r --remove-destination -v kernel-$kernelversion/. $kerneldir
  for bp in $kerneldir/*.bash ; do source $bp                                             ; $sudo rm -rf $bp ; done
  for bp in $kerneldir/*.patch; do echo $bp ; $sudo patch -d $kerneldir -p1 -N -r - < $bp ; $sudo rm -rf $bp ; done
  $sudo make $makeoptions KCONFIG_ALLCONFIG=.config allnoconfig # only add config entries added in diff.patch or script.bash
  diff -Naur  $kerneldir/before.config $kerneldir/.config >config-changes.diff
  $sudo rm -f $kerneldir/before.config
  $sudo make $makeoptions $makej scripts modules_prepare
  kernelrelease=$($sudo make -s $makeoptions kernelrelease)
  $sudo make $makeoptions $makej UIMAGE_LOADADDR=0x40008000 Image dtbs modules # Remove UIMAGE_LOADADDR= ???
  [[ $? != 0 ]] && exit  
  $sudo mkimage -A arm64 -O linux -T kernel -C none -a 40080000 -e 40080000 -n "Linux Kernel $kernelrelease" \
                -d $kerneldir/arch/arm64/boot/Image $kerneldir/uImage
  $sudo mkdir -p $rootfsdir/boot/
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

### COMPRESS IMAGE FROM SD-CARD OR LOOP_DEV ###
if [ "$c" = true ] && [[ $IMAGE_SIZE_MB != "" ]]; then
  unmountrootfs
  $sudo zerofree -v $mountdev
  if [ "$USE_LOOPDEV" == true ]; then
    detachloopdev
    echo "Creating image..."
    xz --keep --force --verbose $IMAGE_FILE
  else
    $sudo dd bs=1M count=$IMAGE_SIZE_MB if="${device}" status=progress | xz >$IMAGE_FILE.xz
  fi
fi
exit


