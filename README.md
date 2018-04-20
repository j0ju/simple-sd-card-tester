# simple-sd-card-tester

This is a simple SD/MMC card tester on block level with simple benchmarking features.
It is written in shell with the help and use of GNU userland on Linux.

# Needs
 * sed
 * dd (uses oflags=direct, iflags=fullblock)
 * md5sum
 * tee
 * POSIX shell

# Usage

>        test-sd-card.sh - a simple SD card testing tool, with small benchmarking features
>        
>          usage: test-sd-card.sh [opt] [opt] ... [blockdevice]
>        
>            opts:
>              -B              display output of dd instances    (no)
>              -P              page size in Kilo Bytes           (4 MiBi)
>              -W              write size in Kilo Bytes          (1 GiBi)
>              -f              full write of blockdevice         (no)
>                              (page size == write size)
>              --keep-data     keep data files                   (no)
>              --keep-checksum keep data files                   (no)
>              --source        source device                     ($SOURCE)
>        
>          hints:
>            * Usually you have a simple wrap around in address lanes on bad
>              SD/MMC cards. This results in data written at the wrap around
>              memory, erasing the beginning of the card.
>            * If the MMC/SD card has a better FTL in place, a full write
>              is needed as it tracks the written areas of the embedded flash.
>              If a quick scan does not discover errors, use -f, if suspicous.

# Examples

## Test SD card at /dev/sdc parttially, withput benchmark output
>          sh test-sd-card.sh /dev/sdc
This would write currently 4 MiBi at every 1G of the block device of the SD card.
It would detect wrap around errors on cheap SD/MMC cards with or without a stupid FTL (flash transaction layer)
A bad flash chip with a good FTL would fool that test.

## Test SD card at /dev/sdc partially, with 64MiBi page size and 1MiBi
>          sh test-sd-card.sh /dev/sdc -P 65536 -W 1024

## Test SD card at /dev/sdc fully, with 64MiBi pages
>          sh test-sd-card.sh /dev/sdc -f -P 65536

This would write the SD card in 64MiBi pages.
It would detect FTL and wrap around errors on cheap SD/MMC cards.

## Test SD card at /dev/sdc fully, with 64MiBi pages, and simple benchmarking output
>          sh test-sd-card.sh /dev/sdc -f -P 65536 -B

# ToDo / Bugs
 * -W & -P accept KiBi bytes, but internally everything is done MiBi bytes, so using -W and -P with values less than 1024, would break that script.
 * used pipes and checksum files are not cleaned up on error exit/^C/... (not yet, use trap)
 * use mktemp, etc. for tempfiles

# License
GPL, see `LICENSE` file
