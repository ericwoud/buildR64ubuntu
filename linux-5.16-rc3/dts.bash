#!/bin/bash

$sudo sed -i "/bootargs/c \\\t\tbootargs = \"$KERNELBOOTARGS\";" \
   $kerneldir/arch/arm64/boot/dts/mediatek/$KERNELDTB.dts

