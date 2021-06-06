/*
 * echo-bpir64-mbr - Echo MBR for BPI R64
 *
 * partition_table[0] is a partition that tells mbr tools,
 * all blocks on the device are reserved, are used by gpt.
 * This prevents this tool sees unused blocks and 
 * overwrites them.
 *
 * partition_table[1] is the bl2 partition, if defined.
 *
 */
  
#define _GNU_SOURCE

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <linux/fs.h>

#define MBR_COPY_PROTECTED        0x5A5A

#define MBR_STATUS_NON_BOOTABLE     0x00
#define MBR_STATUS_BOOTABLE         0x80

#define MBR_TYPE_UNUSED             0x00
#define MBR_TYPE_EFI_GPT            0xEE
#define MBR_TYPE_EFI                0xEF

#define MBR_BOOT_SIGNATURE        0xAA55

typedef struct {
    uint8_t                   status;
    struct {
        uint8_t                 h;
        __le16                  cs;
    } __attribute__((packed)) start_chs;
    uint8_t            type;
    struct {
        uint8_t                 h;
        __le16                  cs;
    } __attribute__((packed)) end_chs;
    __le32                    starting_lba;
    __le32                    number_of_sectors;
}  __attribute__((packed)) partition_t;

typedef struct {
    uint8_t                   bootstrap_code[440];
    __le32                    disk_signiture;
    __le16                    copy_protected;
    partition_t               partition_table[4];
    __le16                    boot_signature;
}  __attribute__((packed))  mbr_t;

static void usage(void)
{
  fprintf(stderr, "Usage:\n"
  "echo-bpir64-mbr {sdmmc|emmc} [start size]\n"
  "  sdmmc          echo mbr of sdmmc boot\n"
  "  emmc           echo mbr of emmc boot\n"
  "  start size     sectors of sdmmc bl2 partition");
  exit(1);
}

int main (int argc, char **argv) {

  mbr_t mbr_sdmmc = {
    .disk_signiture     = 0xb863ab8b,
    .copy_protected     = 0,

    .partition_table[0].status = MBR_STATUS_NON_BOOTABLE,
    .partition_table[0].start_chs.h = 0,
    .partition_table[0].start_chs.cs = 2,
    .partition_table[0].type = MBR_TYPE_EFI_GPT,
    .partition_table[0].end_chs.h = 0xff,
    .partition_table[0].end_chs.cs = 0xffff,
    .partition_table[0].starting_lba = 1,
    .partition_table[0].number_of_sectors = 0xffffffff,
    
    .partition_table[1].status = MBR_STATUS_BOOTABLE,
    .partition_table[1].start_chs.h = 0,
    .partition_table[1].start_chs.cs = 0,
    .partition_table[1].type = MBR_TYPE_EFI,
    .partition_table[1].end_chs.h = 0,
    .partition_table[1].end_chs.cs = 0,
    .partition_table[1].starting_lba = 0x400,
    .partition_table[1].number_of_sectors = 0x400,

    .boot_signature = MBR_BOOT_SIGNATURE,
        };
 
  mbr_t mbr_emmc = {
    .disk_signiture     = 0,
    .copy_protected     = 0,
    
    .partition_table[0].status = MBR_STATUS_NON_BOOTABLE,
    .partition_table[0].start_chs.h = 0,
    .partition_table[0].start_chs.cs = 2,
    .partition_table[0].type = MBR_TYPE_EFI_GPT,
    .partition_table[0].end_chs.h = 0xff,
    .partition_table[0].end_chs.cs = 0xffff,
    .partition_table[0].starting_lba = 1,
    .partition_table[0].number_of_sectors = 0x00e8ffff,

    .boot_signature = MBR_BOOT_SIGNATURE,
        };
  
  if (argc < 2) usage();
  if (strcmp(argv[1], "sdmmc") == 0) {
    if (argc == 4) {
      if ((mbr_sdmmc.partition_table[1].starting_lba      = atoi(argv[2])) == 0 ) usage();
      if ((mbr_sdmmc.partition_table[1].number_of_sectors = atoi(argv[3])) == 0 ) usage();
    }
    write(STDOUT_FILENO, &mbr_sdmmc, sizeof(mbr_sdmmc));
  } else if (strcmp(argv[1], "emmc") == 0) {
    write(STDOUT_FILENO, &mbr_emmc, sizeof(mbr_emmc));
  } else {
    usage();
  }
  return 0;
}
