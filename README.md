# buildR64ubuntu

Install a minimal Arch-Linux, Ubuntu or Debian on Banana Pi R64 from scratch. 

Based on: [buildWubuntu](https://github.com/ericwoud/buildWubuntu.git)
, [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
and [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)

Now includes a patch so that temperature is regulated at 87 instead of 47 degrees!
Delete the file thermal_cpu.patch before building, if you do not want to.

The script is in development and uses sudo. Any bug may possibly delete everything permanently!

USE AT YOUR OWN RISK!!!

## Getting Started

You need:

  - Banana Pi R64
  - SD card

### Prerequisites

Take a look with the script at the original formatting of the SD card. We use this info to determine it's page/erase size.

### Installing


Clone from Git

```
git clone https://github.com/ericwoud/buildR64ubuntu.git
```

Change directory

```
cd buildR64ubuntu
```

Install all necessary packages with:
```
./build.sh -a
```
Check your SD card with the following command, write down where the original first partition starts! The script will first show you this info before formatting anything. Set SD_BLOCK_SIZE_KB and SD_ERASE_SIZE_MB in the script as described there. Don't format a brand new SD card before you find the original erase/block size. It is the best way to determine this.
```
./build.sh -SD
```
Now format your SD card with the same command.

Now build the root filesystem, boot images and kernel.

```
./build.sh
```

## Deployment

Insert the SD card,, powerup, connect to the R64 wireless, SSID: WIFI24, password: justsomepassword. To start ssh to R64, password admin

```
ssh root@192.168.5.1
```
IPforward is on, the system is setup as router.

After this, you are on your own. It is supposed to be a minimal installation of Ubuntu.

When you need to build a kernel on the R64 or build in-tree/out-of-tree kernel modules, first execute the following on the R64:

```
./build.sh -akp
```
It helps set up the build scripts correctly (build tools as arm64 executable instead of x86 executable). Also does 'make distclean' on all sources.

## Using pre-build images for a quick try-out

On github you will find downloadable images at the release branches.

Write the image file for sd-card to the appropriate device, MAKE SURE YOU HAVE THE CORRECT DEVICE!
```
xz -dcv ~/Downloads/imagename-sdmmc.img.xz | sudo dd of=/dev/sda
```
If you want, copy the imagename-emmc.img.xz image to the sd-card (mount with nautilus or disks):
```
sudo cp ~/Downloads/imagename-emmc.img.xz /media/$USER/BPI-ROOT/root/
```
Boot from sd-card and log in through wifi, lan or serial. Then enable boot from mmcblk0 and write the image:
```
mmc bootpart enable 7 1 /dev/mmcblk0
xz -dcv imagename-emmc.img.xz | dd of=/dev/mmcblk0
```
Remove sd-card and boot from emmc, or switch bootswitch.

## Build/Install emmc version

When building on R64 (running on sd-card) start/re-enter a screen session with:
```
screen -R
```
Detach from the session if you want, with CTRL-A + D.

Change ATFDEVICE=sdmmc in the script to emmc. Now format the emmc:
```
./build.sh -SD
```

Make sure your internet connection is working on the R64. Ping 8.8.8.8 should work. 

Now build the whole image, same as before.


## Using port 5 of the dsa switch

Note: This does not work when running from emmc and the bootswitch is set to try from sdmmc first, position 1. Only onder these two conditions combined, it seems eth1 does not get initialised correctly. The eth1 gmac works fine running from emmc, with sw1 set to 0, try boot from emmc first.

Follow the steps below if you want to use a Router setup and run on emmc with sw1 set to 1. You will then not be using eth1 and port 5 of the dsa switch 

Port 5 is available and named aux. Wan and aux port are in a separate vlan. Eth1 is setup as outgoing port instead of wan port.

One would expect the traffic goes a sort of ping pong slow software path: wan --- cpu --- eth0 --- dsa driver --- eth0 --- cpu --- aux --- eth1. But in fact it seems like hardware offloading kicks in and traffic is forwarded in the switch hardware from wan to aux, not taking the slow software path. Exactly what we want: wan --- aux --- eth1. ifstat shows us the traffic is not passing eth0 anymore.
```
ifstat -wi eth0,eth1
```
If you don't like this trick, then:

* Move 'DHCP=yes', under 'Network', from 10-eth1.network to 10-wan.network.
* Remove 'aux' from 10-wan.network file.
* Remove 'Bridge=brlan' from 10-wan.network file.
* Remove whole 'BridgeVLAN' section from 10-wan.network file.
* Remove 10-eth1.network file
* Adjust nftables.conf as described in the file.


## Setup as Access Point

When using a second or third R64ubuntu as Access Point, and connecting router-lan-port to AP-lan-port, do the following: 

Change SETUP="RT" to SETUP="AP".

The Access Point has network address 192.168.1.33.

For vlan setup the lan ports which connect router and AP as lan-trunk port on both router and AP. 

Some DSA drivers have a problem with this setup, but some are recently fixed with a fix wireless roaming fix in the kernel. You will need very recent drivers on all routers/switches and access points on your network


## TODO:

* Implement 802.11k 802.11r 802.11v.
* MyGica T230C2 DVB-T and DVB-C support.
* Guest WIFI

## Major update 31-08-2021

* Able to install Arch-Linux, it is also now the default. Guess the repo needs a name change.
* Using systemd's dhcp server.
* Using systemd-resolved
* Many other small changes

## Features

* Ubuntu Focal
* Kernel v5.12
* Much faster startup due to changing from ifupdown (/etc/network/interfaces)
  to systemd-networkd.service (/etc/systemd/network).
* Build on R64
* New bootheader fix, no need for mmcblk0boot0, but still use GPT.
* Build sdmmc and emmc version
* Build/install emmc version when running on the sdmmc version.
* Write to image file instead of sd-card. To examine the result, use GNOME Disks -> menu -> "Attach Disk Image"
* Files copied from custom kernel and rootfs directory.
* Enable custom services installed from rootfs-xxx/etc/systemd/system
* Optional scripts in the custom kernel and rootfs directory. Files with extention ".bash" 
  Environment and variables from main script can be used.
* Optional patches in the custom kernel and rootfs directory. Files with extention ".patch"
* -a : Install necessairy packages.
* -SD : Format SD card
* -r : Build RootFS.
* -b : Build Boot images.
* -k : Build Kernel.
* -c : Builds Compressed archive from SD-card or loop-device.
* -t : Create Tar archives to save time next time building.
* -p : Make modules_prepare only. Also makes clean and build scripts. Use together with -k
* -m : Make menuconfig only. Use together with -k
* -R : Delete RootFS.
* -K : Delete Kernel.
* -F : Delete Firmware.
* -T : Delete Tar archives
* -B : Delete Boot sources.
* Default options when no options entered -brkta
* Adding extra packages to install. See EXTRAPACKAGES= at top of build script.
* Other variables to tweak also at top of build script. Try building a different release or kernel version.
* Adding kernel options from custom script (see example T230C2)

## Acknowledgments

* [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
* [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)
* [mtk-openwrt-atf](https://github.com/mtk-openwrt/arm-trusted-firmware)
* [u-boot](https://github.com/u-boot/u-boot)
* [McDebian](https://github.com/Chadster766/McDebian)

