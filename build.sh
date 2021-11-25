#!/bin/bash

GCC=""   # use standard ubuntu gcc version
#GCC="https://releases.linaro.org/components/toolchain/binaries/latest-7/aarch64-linux-gnu/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz"

SRC=""                 # Installs source in /usr/src of sd-card/image
#SRC="./src"           # Installs source in same folder as build.sh
#SRC="/usr/src"        # When running on sd-card, use the same source to build emmc 

KERNELVERSION="5.15-rc1"        # Custom Kernel files in folder named 'linux-5.12'
#KERNELVERSION="master"          # master (head) of git, name folder 'linux-master'

#KERNEL="http://kernel.ubuntu.com/~kernel-ppa/mainline"
#KERNEL="https://github.com/torvalds/linux.git"
#KERNEL="https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$KERNELVERSION.tar.xz"
#KERNEL="https://git.kernel.org/torvalds/t/linux-$KERNELVERSION.tar.gz"
KERNEL="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot/linux-$KERNELVERSION.tar.gz"
#KERNEL="https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git"

KERNELLOCALVERSION="-0"      # Is added to KERNELVERSION by make for name of modules dir.

KERNELDTB="mt7622-bananapi-bpi-r64"
UBOOTDTB="mt7622-bananapi-bpi-r64"

ATFGIT="https://github.com/mtk-openwrt/arm-trusted-firmware.git"
ATFBRANCH="mtksoc"  # Was fixed in commit a63914612904642ed974390fff620f7003ebc20a

ATFDEVICE="sdmmc"
#ATFDEVICE="emmc"

#https://git.openwrt.org/?p=openwrt/openwrt.git;a=blob;f=package/boot/arm-trusted-firmware-mediatek/Makefile
ATFBUILDARGS="PLAT=mt7622 BOOT_DEVICE=$ATFDEVICE DDR3_FLYBY=1 LOG_LEVEL=40" # (50 = LOG_LEVEL_VERBOSE)

#USE_UBOOT="true"          # bootchain with (or without) U-Boot

UBOOTGIT="https://github.com/u-boot/u-boot.git"
UBOOTBRANCH="v2021.10-rc3"

KERNELBOOTARGS="console=ttyS0,115200 rw rootwait root=PARTLABEL=root-bpir64-${ATFDEVICE}"

# Uncomment if you do not want to use a SD card, but a loop-device instead.
#USE_LOOPDEV="true"          # Remove SD card, because of same label

IMAGE_FILE="./my-bpir64-"$ATFDEVICE".img"
#IMAGE_FILE="/media/$USER/FILES//my-bpir64-"$ATFDEVICE".img"

# https://github.com/bradfa/flashbench.git, running multiple times:
# sudo ./flashbench -a --count=64 --blocksize=1024 /dev/sda
# Shows me that times increase at alignment of 8k
# On f2fs it is used for wanted-sector-size, but sector size is stuck at 512
SD_BLOCK_SIZE_KB=8                   # in kilo bytes
# When the SD card was brand new, formatted by the manufacturer, parted shows partition start at 4MiB
# 1      4,00MiB  29872MiB  29868MiB  primary  fat32        lba
# Also, once runnig on BPIR64 execute:
# bc -l <<<"$(cat /sys/block/mmcblk1/device/preferred_erase_size) /1024 /1024"
# bc -l <<<"$(cat /sys/block/mmcblk1/queue/discard_granularity) /1024 /1024"
SD_ERASE_SIZE_MB=4                   # in Mega bytes

IMAGE_SIZE_MB=7456                # Size of image
ATF_END_KB=1024                   # End of atf partition
MINIMAL_SIZE_FIP_MB=15             # Minimal size of fip partition

#ROOTFS_FS="ext4"
ROOTFS_FS="f2fs"
ROOTFS_LABEL="BPI-ROOT"

ROOTFS_EXT4_OPTIONS=""
#ROOTFS_EXT4_OPTIONS="-O ^has_journal"  # No journal is faster, but you can get errors after powerloss


# Choose one of the three following linux distributions:

### UBUNTU ###
#RELEASE="focal"
#DEBOOTSTR_SOURCE="http://ports.ubuntu.com/ubuntu-ports"
#DEBOOTSTR_COMPNS="main,restricted,universe,multiverse"

### DEBIAN ###
#RELEASE="buster"
#DEBOOTSTR_SOURCE="http://ftp.debian.org/debian/"
#DEBOOTSTR_COMPNS="main,contrib,non-free"

### ARCH LINUX ###
RELEASE="arch"
ARCHBOOTSTRAP="https://raw.githubusercontent.com/tokland/arch-bootstrap/master/arch-bootstrap.sh"

# Packages installed in rootfs, comma separated list, no spaces
NEEDED_PACKAGES_DEBIAN="locales,hostapd,openssh-server,crda,iproute2,nftables"
EXTRA_PACKAGES_DEBIAN="vim,screen,mmc-utils"
# Space separated
SCRIPT_PACKAGES_DEBIAN="build-essential git debootstrap wget flex bison \
u-boot-tools libncurses-dev libssl-dev zerofree symlinks bc ca-certificates parted gzip \
arch-install-scripts udisks2 f2fs-tools"

NEEDED_PACKAGES_ARCHLX="base hostapd openssh crda iproute2 nftables"
EXTRA_PACKAGES_ARCHLX="vim screen"
SCRIPT_PACKAGES_ARCHLX="base-devel git debootstrap wget uboot-tools ncurses openssl \
bc ca-certificates parted gzip arch-install-scripts udisks2 f2fs-tools"
SCRIPT_PACKAGES_AUR="zerofree symlinks mmc-utils-git"

SETUP="RT"   # Setup as RouTer
#SETUP="AP"  # Setup as Access Point

LC="en_US.utf8"                      # Locale
TIMEZONE="Europe/Paris"              # Timezone
ROOTPWD="admin"                      # Root password


[ "$USE_UBOOT" == true ] && ROOTFS_FS="ext4" # f2fs not supported in U-Boot


export LC_ALL=C
export LANG=C
export LANGUAGE=C

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
  else
    echo ROOTDEV: $rootdev
    lsblkrootdev=($(lsblk -prno name,pkname,partlabel | grep $rootdev))
    [ -z $lsblkrootdev ] && exit
    realrootdev=${lsblkrootdev[1]}
    readarray -t options < <(lsblk --nodeps -no name,serial,size \
                      | grep -v "^"${realrootdev/"/dev/"/}'\|^loop' \
                      | grep -v 'boot0 \|boot1 \|boot2 ')
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
  minimalrootstart=$(( $ATF_END_KB + ($MINIMAL_SIZE_FIP_MB * 1024) ))
  rootstart=0
  while [[ $rootstart -lt $minimalrootstart ]]; do 
    rootstart=$(( $rootstart + ($SD_ERASE_SIZE_MB * 1024) ))
  done
  $sudo dd of="${device}" if=/dev/zero bs=1024 count=$rootstart
  $sudo parted -s -- "${device}" unit kiB \
    mklabel gpt \
    mkpart primary $rootstart 100% \
    mkpart primary $ATF_END_KB $rootstart \
    mkpart primary 0% $ATF_END_KB \
    name 1 root-bpir64-${ATFDEVICE} \
    name 2 fip \
    name 3 atf \
    print
  $sudo partprobe "${device}"
  lsblkdev=""
  while [ -z $lsblkdev ]; do
    lsblkdev=($(lsblk -prno name,pkname,partlabel ${device}| grep root-bpir64-${ATFDEVICE}))
    sleep 0.1
  done
  mountdev=${lsblkdev[0]}
  echo "Root Filesystem:" $ROOTFS_FS
  $sudo blkdiscard -fv "${mountdev}"
  if [ $ROOTFS_FS = "ext4" ];then
    [[ $SD_BLOCK_SIZE_KB -lt 4 ]] && blksize=$SD_BLOCK_SIZE_KB || blksize=4
    stride=$(( $SD_BLOCK_SIZE_KB / $blksize ))
    stripe=$(( ($SD_ERASE_SIZE_MB * 1024) / $SD_BLOCK_SIZE_KB ))
    $sudo mkfs.ext4 -v $ROOTFS_EXT4_OPTIONS -b $(( $blksize * 1024 ))  -L $ROOTFS_LABEL \
                    -E stride=$stride,stripe-width=$stripe "${mountdev}"
  elif [ $ROOTFS_FS = "f2fs" ];then
    nrseg=$(( $SD_ERASE_SIZE_MB / 2 )); [[ $nrseg -lt 1 ]] && nrseg=1
    $sudo mkfs.f2fs -w $(( $SD_BLOCK_SIZE_KB * 1024 )) -s $nrseg \
                    -f -l $ROOTFS_LABEL "${mountdev}"
  else
    echo "File System not supported"; exit
  fi
  $sudo sync
  if [ -b ${device}"boot0" ] && [ $bpir64 == "true" ]; then
    $sudo mmc bootpart enable 7 1 ${device}
  fi
  $sudo lsblk -o name,mountpoint,label,size,uuid "${device}"
}

function writefip {
  if [ -f "$1" ]; then
    $sudo dd of="${mountdev::-1}2" if=/dev/zero 2>/dev/null
    $sudo dd of="${mountdev::-1}2" if=$1
  fi
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
  exec > >(tee -i build.log)        # Needs -i for propper CTRL-C trap
  exec 2> >(tee build-error.log)    # Without -i, git hangs?
fi

echo "Target device="$ATFDEVICE
if [ "$(tr -d '\0' 2>/dev/null </proc/device-tree/model)" != "Bananapi BPI-R64" ]; then
  echo "Not running on Bananapi BPI-R64"
  bpir64="false"
else
  echo "Running on Bananapi BPI-R64"
  bpir64="true"
  GCC=""
fi
if [ $ATFDEVICE = "emmc" ];then
  ubootdevnr=0
else
  ubootdevnr=1
fi

if [ "$a" = true ]; then
  if [ ! -f "/etc/arch-release" ]; then ### Ubuntu / Debian
    $sudo apt-get install --yes $SCRIPT_PACKAGES_DEBIAN
    if [ $bpir64 != "true" ]; then
      $sudo apt-get install --yes qemu-user-static gcc-aarch64-linux-gnu libc6:i386 
    fi
  else ### Archlinux
    $sudo pacman -Syu --needed --noconfirm $SCRIPT_PACKAGES_ARCHLX
    ./rootfs-arch/usr/local/sbin/aurinstall $SCRIPT_PACKAGES_AUR
    if [ $bpir64 != "true" ]; then # Not running on BPI-R64
      $sudo pacman -Syu --needed --noconfirm aarch64-linux-gnu-gcc
      ./rootfs-arch/usr/local/sbin/aurinstall binfmt-qemu-static qemu-user-static-bin
    fi
  fi
  if [ $bpir64 != "true" ]; then
    gccname=$(basename $GCC)
    if [ ! -z $GCC ]; then
      wget -nv -N $GCC
      rm -rf gcc
      mkdir gcc
      tar -xf $gccname -C gcc  
    fi
  fi
fi

rootdev=$(lsblk -pilno name,type,mountpoint | grep -G 'part /$')
rootdev=${rootdev%% *}
loopdev=""
lsblkdev=($(lsblk -prno name,pkname,partlabel | grep root-bpir64-${ATFDEVICE}))
if [ ! -z $lsblkdev ]; then
  mountdev=${lsblkdev[0]}
  device=${lsblkdev[1]}
else
  mountdev=""
  device=""
fi
if [ "$USE_LOOPDEV" == true ]; then
  [ ! -z $mountdev ] && echo "WARNING: Be carefull, another ${ATFDEVICE}-image is also inserted!"
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
  if [ "$rootdev" == "$mountdev" ];then
    rootfsdir="" ; r="" ; R=""      # Protect root when running from it!
  else
    rootfsdir=/mnt/bpirootfs
    $sudo umount $mountdev
  fi
fi
sectorsize=$(cat /sys/block/${device/"/dev/"/}/queue/hw_sector_size)
if [ ! -z $rootfsdir ]; then
  [ -d $rootfsdir ] || $sudo mkdir $rootfsdir
  $sudo mount --source $mountdev --target $rootfsdir \
              -o exec,dev,noatime,nodiratime
fi

schroot="$sudo chroot $rootfsdir"
[ -z $SRC ] && src=$rootfsdir/usr/src || src=$(realpath $SRC)
[ -z $rootfsdir ] && src="/usr/src"
src=$(realpath $src)
kerneldir=$src/linux-$KERNELVERSION
echo OPTIONS: rootfs=$r boot=$b kernel=$k tar=$t apt=$a 
if [ "$K" = true ] ; then
  echo Removing kernelsource...
  $sudo rm -rf $kerneldir
fi
if [ "$R" = true ] ; then
  echo Removing rootfs...
  $sudo rm -rf $rootfsdir/!(usr)
  $sudo rm -rf $rootfsdir/usr/!(src)
  $sudo rm -rf $rootfsdir/.*
fi
if [ "$T" = true ] ; then
  echo Removing .tar...
  rm -f rootfs.$RELEASE.tar.bz2 linux-$KERNELVERSION.tar.xz
fi
if [ "$B" = true ] ; then
  echo Removing boot...
  $sudo rm -rf $src/uboot-$UBOOTBRANCH
  $sudo rm -rf $src/atf-$ATFBRANCH
fi
if [ "$F" = true ] ; then
  echo Removing firmware...
  $sudo rm -rf $rootfsdir/lib/firmware
fi
$sudo rmdir --ignore-fail-on-non-empty -p $rootfsdir/usr/src
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
echo "SETUP="$SETUP
echo "Rootfsdir="$rootfsdir
echo "Src="$src
echo "Crossc="$crossc
echo "Device="$device"   sectorsize="$sectorsize
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
      if [ "$RELEASE" != "arch" ]; then
        packages=$NEEDED_PACKAGES_DEBIAN","$EXTRA_PACKAGES_DEBIAN
        [[ -f "rootfs-$RELEASE/etc/network/interfaces" ]] && packages="$packages,ifupdown"
        $sudo debootstrap --arch=arm64 --foreign --no-check-gpg --components=$DEBOOTSTR_COMPNS \
          --include="$packages" $RELEASE $rootfsdir $DEBOOTSTR_SOURCE
        $sudo cp /usr/bin/qemu-aarch64-static $rootfsdir/usr/bin/
        $schroot /debootstrap/debootstrap --second-stage
      else  ### install Arch Linux
        if [ -f "/etc/arch-release" ]; then ### from from Arch Linux
          $sudo systemctl start systemd-binfmt
        fi
        wget --no-verbose $ARCHBOOTSTRAP --no-clobber -P ./tools/
        $sudo bash ./tools/$(basename $ARCHBOOTSTRAP) -q -a aarch64 $rootfsdir 2>&0
        $sudo arch-chroot $rootfsdir /usr/bin/pacman --noconfirm --arch aarch64 -Sy \
              --overwrite \* $NEEDED_PACKAGES_ARCHLX $EXTRA_PACKAGES_ARCHLX
        yes | $sudo arch-chroot $rootfsdir /usr/bin/pacman -Scc
      fi  
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
  symlinks -cr rootfs-*/
  $sudo cp -r --remove-destination --dereference -v rootfs-$RELEASE/. $rootfsdir
  for bp in $rootfsdir/*.bash ; do source $bp                                             ; $sudo rm -rf $bp ; done
  for bp in $rootfsdir/*.patch; do echo $bp ; $sudo patch -d $rootfsdir -p1 -N -r - < $bp ; $sudo rm -rf $bp ; done
  [[ -d "$rootfsdir/etc/systemd/network" ]] && $schroot systemctl reenable systemd-networkd.service
  find -L "rootfs-$RELEASE/etc/systemd/system" -name "*.service"| while read service ; do
    $schroot systemctl reenable $(basename $service)
  done
  $sudo mkdir -p $rootfsdir/root/buildR64ubuntu
  $sudo cp -rfv --no-dereference linux-*/ $rootfsdir/root/buildR64ubuntu/
  $sudo cp -rfv --no-dereference rootfs-*/ $rootfsdir/root/buildR64ubuntu/
  $sudo cp -rfv --no-dereference uboot-*/  $rootfsdir/root/buildR64ubuntu/
  $sudo cp -rfv --no-dereference atf-*/    $rootfsdir/root/buildR64ubuntu/
  $sudo cp -rfv --no-dereference tools/    $rootfsdir/root/buildR64ubuntu/
  $sudo cp -fv build.sh $rootfsdir/root/buildR64ubuntu/
fi

### BOOT ###
if [ "$b" = true ]; then
  mountdevname=${mountdev/"/dev/"/}
  firstavailblock=$(cat "/sys/class/block/"${mountdevname::-1}3"/start")
  $sudo mkdir -p $src/
  if [ ! -d "$src/atf-$ATFBRANCH" ]; then
    $sudo git --no-pager clone --branch $ATFBRANCH --depth 1 $ATFGIT $src/atf-$ATFBRANCH 2>&0
    [[ $? != 0 ]] && exit
  fi
  if [ ! -d "$src/uboot-$UBOOTBRANCH" ]; then  
    $sudo git --no-pager clone --branch $UBOOTBRANCH --depth 1 $UBOOTGIT $src/uboot-$UBOOTBRANCH 2>&0
    [[ $? != 0 ]] && exit
  fi
  sudo touch $src/atf-$ATFBRANCH/plat/mediatek/mt7622/platform.mk
  for bp in ./atf-$ATFBRANCH/*.bash ;     do source $bp ; done
  for bp in ./uboot-$UBOOTBRANCH/*.bash ; do source $bp ; done
  for bp in ./atf-$ATFBRANCH/*.patch;     do echo $bp ; $sudo patch -d $src/atf-$ATFBRANCH      -p1 -N -r - < $bp ; done
  for bp in ./uboot-$UBOOTBRANCH/*.patch; do echo $bp ; $sudo patch -d  $src/uboot-$UBOOTBRANCH -p1 -N -r - < $bp ; done
  make -j1 --directory=./tools/ clean all # -j1 so first clean then all
  [[ $? != 0 ]] && exit
  mkimage="USE_MKIMAGE=1 MKIMAGE=$src/uboot-$UBOOTBRANCH/tools/mkimage DEVICE_HEADER_OFFSET=0"
  makeatf="$sudo make $makej $crossc --directory=$src/atf-$ATFBRANCH $ATFBUILDARGS $mkimage"
  # PRELOADED_BL33_BASE is not being used in mt7622 atf code, so we use it as binairy flags:
  # 0b0001 : incbin BL31.bin inside of BL2 image, disable it during BL31 build because of common code!
  [ "$USE_UBOOT" == true ] && ubtarget="all" || ubtarget="tools-only"
  ARCH=arm64 $sudo make $makej $crossc --directory=$src/uboot-$UBOOTBRANCH mt7622_my_bpi_defconfig $ubtarget
  [[ $? != 0 ]] && exit
  $makeatf PRELOADED_BL33_BASE=0b0000 bl31 fiptool
  [[ $? != 0 ]] && exit
  $makeatf PRELOADED_BL33_BASE=0b0001 bl2 $src/atf-$ATFBRANCH/build/mt7622/release/bl2.img
  [[ $? != 0 ]] && exit
  if [ "$USE_UBOOT" == true ]; then
    $sudo $src/atf-$ATFBRANCH/tools/fiptool/fiptool --verbose create $src/atf-$ATFBRANCH/build/mt7622/release/fip.bin \
                --nt-fw $src/uboot-$UBOOTBRANCH/u-boot.bin
    $sudo $src/atf-$ATFBRANCH/tools/fiptool/fiptool info $src/atf-$ATFBRANCH/build/mt7622/release/fip.bin
    writefip $src/atf-$ATFBRANCH/build/mt7622/release/fip.bin
  fi
  $sudo dd of="${mountdev::-1}3" if=/dev/zero 2>/dev/null
  $sudo dd of="${device}" bs=1 count=440 \
           if=$src/atf-$ATFBRANCH/build/mt7622/release/bl2.img
  $sudo dd of="${mountdev::-1}3" skip=$firstavailblock \
           if=$src/atf-$ATFBRANCH/build/mt7622/release/bl2.img
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
    if [ ! -f "linux-$KERNELVERSION.tar.xz" ] && [ ! -f "linux-$KERNELVERSION.tar.gz" ]; then
      if [ ${KERNEL: -4} == ".git" ]; then
        [ $KERNELVERSION != "master" ] && branch="--branch v"$KERNELVERSION || branch=""
        $sudo git --no-pager clone --depth 1 $branch $KERNEL $kerneldir 2>&0
        [[ $? != 0 ]] && exit
        $sudo rm -rf $kerneldir/.git
      elif [ ${KERNEL: -7} == ".tar.xz" ] || [ ${KERNEL: -7} == ".tar.gz" ]; then
        echo "Downloading $KERNEL..."
        wget -nv -N $KERNEL
      else # Ubuntu mainline
        gitbranch=$(wget -nv -qO- $KERNEL/v$KERNELVERSION/HEADER.html | grep -m 1 git://)
        gitbranch=${gitbranch//&nbsp;/}
        gitbranch=(${gitbranch//<br>/})
        $sudo git --no-pager clone --branch ${gitbranch[1]} --depth 1 ${gitbranch[0]} $kerneldir 2>&0
        [[ $? != 0 ]] && exit
        $sudo rm -rf $kerneldir/.git
        sources=$(wget -nv -qO- $KERNEL/v$KERNELVERSION/SOURCES) ; readarray -t sources <<<"$sources"
        if [ ! -z "${sources[0]}" ]; then # has SOURCES file
          psrc=1
          while [ $psrc -lt ${#sources[@]} ]; do
            wget -nv -O /dev/stdout $KERNEL/v$KERNELVERSION/${sources[$psrc]} | $sudo patch -d $kerneldir -p1
            let psrc++
          done
        fi
      fi
      if [ "$t" = true ] && [ ! -f "linux-$KERNELVERSION.tar.xz" ] && [ ! -f "linux-$KERNELVERSION.tar.gz" ]; then
        echo "Creating linux-tar..."
        tar -cJf linux-$KERNELVERSION.tar.xz -C $kerneldir/.. $(basename $kerneldir)
      fi
    fi
    if [ ! -d "$kerneldir" ] && [ -f "linux-$KERNELVERSION.tar.xz" ]; then
      $sudo mkdir -p $kerneldir
      echo "Extracting linux-tar.xz..."
      $sudo tar -xf linux-$KERNELVERSION.tar.xz -C $kerneldir/..
    elif [ ! -d "$kerneldir" ] &&  [ -f "linux-$KERNELVERSION.tar.gz" ]; then
      $sudo mkdir -p $kerneldir
      echo "Extracting linux-tar.gz..."
      $sudo tar -xf linux-$KERNELVERSION.tar.gz -C $kerneldir/..
    fi
  fi  
  makeoptions="--directory="$kerneldir" LOCALVERSION="$KERNELLOCALVERSION" DEFAULT_HOSTNAME=R64UBUNTU ARCH=arm64 "$crossc" KCFLAGS=-w"
  outoftreeoptions=${makeoptions/--directory=/KDIR=}
  if [ "$p" = true ]; then
    $sudo make $makeoptions scripts modules_prepare distclean
    (cd $src/atf-$ATFBRANCH; $sudo make distclean)
    (cd $src/uboot-$UBOOTBRANCH; $sudo make distclean)
    exit
  fi
  $sudo cp --remove-destination --dereference -v linux-$KERNELVERSION/defconfig $kerneldir/arch/arm64/configs/r64ubuntu_defconfig
  $sudo make $makeoptions r64ubuntu_defconfig
  if [ "$m" = true ] ; then
    echo -e "\nSave altered config as '.config'.\n"
    read -p "Press <enter> to continue..." prompt
    $sudo make $makeoptions menuconfig
#    $sudo make $makeoptions yes2modconfig
    $sudo make $makeoptions savedefconfig 
    format=$(realpath ./tools/formatdefconfig.sh)
    (cd $kerneldir; ARCH=arm64 $sudo $format)
    read -p "Type <save> to save configuration permanently: " prompt
    if [[ $prompt == "save" ]]; then
      cp --remove-destination -v $kerneldir/formatdef/defconfig linux-$KERNELVERSION/defconfig
    fi
    exit  
  fi  
  $sudo cp --remove-destination -v $kerneldir/.config $kerneldir/before.config
  $sudo mkdir -p $kerneldir/outoftree
  symlinks -cr linux-*/
  symlinks -cr rootfs-*/
  $sudo cp -r --remove-destination -v linux-$KERNELVERSION/. $kerneldir
  for bp in $kerneldir/*.bash ; do source $bp                                             ; $sudo rm -rf $bp ; done
  for bp in $kerneldir/*.patch; do echo $bp ; $sudo patch -d $kerneldir -p1 -N -r - < $bp ; $sudo rm -rf $bp ; done
  $sudo make $makeoptions KCONFIG_ALLCONFIG=.config allnoconfig # only add config entries added in diff.patch or script.bash
  diff -Naur  $kerneldir/before.config $kerneldir/.config >config-changes.diff
  $sudo rm -f $kerneldir/before.config
  $sudo make $makeoptions $makej scripts modules_prepare
  kernelrelease=$($sudo make -s $makeoptions kernelrelease)
  $sudo make $makeoptions $makej UIMAGE_LOADADDR=0x40008000 Image dtbs modules # Remove UIMAGE_LOADADDR= ???
  [[ $? != 0 ]] && exit  
  if [ "$USE_UBOOT" == true ]; then
    $sudo mkimage -A arm64 -O linux -T kernel -C none -a 40080000 -e 40080000 -n "Linux Kernel $kernelrelease" \
                  -d $kerneldir/arch/arm64/boot/Image $kerneldir/uImage
    $sudo mkdir -p $rootfsdir/boot/
    $sudo cp -af $kerneldir/arch/arm64/boot/dts/mediatek/$KERNELDTB.dtb $rootfsdir/boot/$kernelrelease.dtb
    $sudo cp -af $kerneldir/uImage $rootfsdir/boot/$kernelrelease.uImage
    $sudo echo -e "image=boot/$kernelrelease.uImage\ndtb=boot/$kernelrelease.dtb" | \
             $sudo tee    $rootfsdir/boot/uEnv.txt
  fi
  $sudo make $makeoptions modules_install INSTALL_MOD_PATH=$rootfsdir
  if [ $kerneldir/outoftree/* != "$kerneldir/outoftree/*" ]; then
    $sudo mkdir -p $rootfsdir/lib/modules/$kernelrelease/extra
    for module in $kerneldir/outoftree/*
    do 
      (cd $module; $sudo make $outoftreeoptions) 
      [[ $? == 0 ]] && $sudo cp -fv $module/*.ko $rootfsdir/lib/modules/$kernelrelease/extra
    done
  fi
  $sudo depmod -ab $rootfsdir/. $kernelrelease
  if [ -z $SRC ]; then 
    $sudo ln -v --force --symbolic --relative --no-dereference $kerneldir $rootfsdir/lib/modules/$kernelrelease/build
    $sudo ln -v --force --symbolic --relative --no-dereference $kerneldir $rootfsdir/lib/modules/$kernelrelease/source
  else
    $sudo rm -vf rootfsdir/lib/modules/$kernelrelease/build
    $sudo rm -vf rootfsdir/lib/modules/$kernelrelease/source
  fi
  if [ "$USE_UBOOT" != true ] && [ -f "$src/atf-$ATFBRANCH/tools/fiptool/fiptool" ]; then
    $sudo mkdir -p $src/atf-$ATFBRANCH/build/mt7622/release/
    $sudo $src/atf-$ATFBRANCH/tools/fiptool/fiptool --verbose create $kerneldir/arch/arm64/boot/fip.bin \
                --nt-fw $kerneldir/arch/arm64/boot/Image \
         --nt-fw-config $kerneldir/arch/arm64/boot/dts/mediatek/$KERNELDTB.dtb
    $sudo $src/atf-$ATFBRANCH/tools/fiptool/fiptool info $kerneldir/arch/arm64/boot/fip.bin
    writefip $kerneldir/arch/arm64/boot/fip.bin
  fi
fi


### COMPRESS IMAGE FROM SD-CARD OR LOOP_DEV ###
if [ "$c" = true ]; then
  unmountrootfs
  [ $ROOTFS_FS = "ext4" ] && $sudo zerofree -v $mountdev
  if [ "$USE_LOOPDEV" == true ]; then
    detachloopdev
    xz --keep --force --verbose $IMAGE_FILE 2>&0
  else
    $sudo dd bs=1M if="${device}" status=progress | xz >$IMAGE_FILE.xz
  fi
fi
exit

