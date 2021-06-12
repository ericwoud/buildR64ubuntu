#!/bin/bash
$sudo cp --no-clobber $src/uboot-$UBOOTBRANCH//tools/mtk_image.h \
                      $src/uboot-$UBOOTBRANCH//tools/mtk_image_orig.h
$sudo cp -f           $src/uboot-$UBOOTBRANCH//tools/mtk_image_orig.h \
                      $src/uboot-$UBOOTBRANCH//tools/mtk_image.h
$sudo patch -d $src/uboot-$UBOOTBRANCH -p1 -N -r - <<EOF
diff -NarU 6 a/tools/mtk_image.h b/tools/mtk_image.h
--- a/tools/mtk_image.h	2021-06-10 20:32:04.156559289 +0200
+++ b/tools/mtk_image.h	2021-06-10 20:32:36.964722097 +0200
@@ -16,13 +16,13 @@
 	struct {
 		char name[12];
 		uint32_t version;
 		uint32_t size;
 	};
 
-	uint8_t pad[0x200];
+	uint8_t pad[ $(( $firstavailblock * 512 )) ];
 };
 
 #define EMMC_BOOT_NAME		"EMMC_BOOT"
 #define SF_BOOT_NAME		"SF_BOOT"
 #define SDMMC_BOOT_NAME		"SDMMC_BOOT"
 
EOF

