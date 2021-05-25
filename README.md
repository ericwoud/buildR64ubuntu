# buildR64ubuntu

Install a minimal Ubuntu on Banana Pi R64 from scratch. 

Based on: [buildWubuntu](https://github.com/ericwoud/buildWubuntu.git)
And: [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
And: [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)

Now includes a patch so that temperature is regulated at 87 instead of 47 degrees!
Delete the file thermal_cpu.patch bofore building, if you do not want to.

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
IPforward is on, the system is setup as router. Also see https://github.com/ericwoud/bridgefdbd to make AP work nicely.

After this, you are on your own. It is supposed to be a minimal installation of Ubuntu.

When you need to build in-tree/out-of-tree kernel modules, first execute the following on the R64:

```
./build.sh -akp
```
It helps set up the build scripts correctly (build tools as arm64 executable instead of x86 executable).


## Using port 5 of the dsa switch

Port 5 is available and named aux. Wan and aux port are in a separate vlan. Eth1 is setup as outgoing port instead of wan port.

One would expect the traffic goes a sort of ping pong slow software path: wan --- cpu --- eth0 --- dsa driver --- eth0 --- cpu --- aux --- eth1. But in fact it seems like hardware offloading kicks in and traffic is forwarded in the switch hardware from wan to aux, not taking the slow software path. Exactly what we want: wan --- aux --- eth1. ifstat shows us the traffic is not passing eth0 anymore.
```
ifstat -wi eth0,eth1
```
If you don't like this trick, then:

* Move 'DHCP=yes', under 'Network', from 10-eth1.network to 10-wan.network.
* Remove 10-eth1.network file
* Remove 'aux' from 10-wan.network file.
* Adjust nftables.conf as described in the file.

## Setup as Access Point

Work in progress...

When using a second or third R64ubuntu as Access Point, and connecting router-lan-port to AP-lan-port, do the following: 

Setup the lan ports which connect router and AP as lan-trunk port on both router and AP. 

On the AP, (remove vet3/eth3 not yet), disable IpForwarding (br0.network), disable isc-dhcp-server. Add the gateway address on the bridge with the address of the router. Change ip address of brlan, stay in the same subnet. 

Most important: use a fix like [FDB Deamon](https://github.com/ericwoud/bridgefdbd) or [Mc Spoof](https://github.com/ericwoud/mcspoof). This is necessairy because there is a problem in the DSA driver.

Note: at the moment bridgefdbd will not work because of an issue with deleting fdb entries in vlan enabled bridge.

## TODO:

* Get FDB delete functions to work, see [vlan enabled bridge bug?](http://forum.banana-pi.org/t/vlan-enabled-bridge-bug/12254)
* Test all new changes in build from scratch.
* Check building on R64.
* Implement 802.11k 802.11r 802.11v.
* Check: build script can run on R64 also, to compile a new kernel.
* MyGica T230C2 DVB-T and DVB-C support.
* Guest WIFI


## Features

* Ubuntu Focal
* Kernel v5.12
* Much faster startup due to changing from ifupdown (/etc/network/interfaces)
  to systemd-networkd.service (/etc/systemd/network).
* Files copied from custom kernel and rootfs directory.
* Enable custom services installed from custom/rootfs/etc/systemd/system
* Optional scripts in the custom kernel and rootfs directory. Files with extention ".bash" 
  Environment and variables from main script can be used.
* Optional patches in the custom kernel and rootfs directory. Files with extention ".patch"
* Creation of archives to save time next time building. Use -t to create -T to delete.
* Install necessairy packages. Use -a
* Build RootFS. Use -r
* Build Kernel. Use -k
* Deletion of RootFS. Use -R
* Deletion of Kernel. Use -K
* Deletion of Firmware. Use -F
* Deletion of Boot sources. Use -B
* Make modules_prepare only. Use -p together with -k
* Make menuconfig only. Use -m together with -k
* Default options when no options entered -brkta
* Adding extra packages to install. See extrapackages= at top of build script.
* Other variables to tweak also at top of build script. Try building a different release or kernel version.
* Adding kernel options from custom script (see example T230C2)


## Acknowledgments

* [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
* [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)
* [mtk-openwrt-atf](https://github.com/mtk-openwrt/arm-trusted-firmware)
* [u-boot](https://github.com/u-boot/u-boot)
* [McDebian](https://github.com/Chadster766/McDebian)

