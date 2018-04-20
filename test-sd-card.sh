#!/bin/sh

# A simple SD card tester
#
# LICENSE:   GPL, see LICENSE file
# Author(s): Joerg Jungermann

set -e

export LC_ALL=C

# devide block device in pages of this size in K and M
# use bs=1M for good speed
PAGE_SIZE_K=$((1024 * 1024)) # 1M * 1k blocks = 1G
#PAGE_SIZE_K=$((256 * 1024)) # 1M * 1k blocks = 1G
#PAGE_SIZE_K=$((64 * 1024)) # 1M * 1k blocks = 1G

# allow only writing parts for quicker testing of sdcards, as you have often simple wrap around fakes
WRITE_SIZE_K=4096
#WRITE_SIZE_K=8192

FULLWRITE=no

KEEP_DATA_FILES=no
KEEP_CHKSUM_FILES=no
BENCHMARK=no

CHKSUM=md5sum
#SOURCE=/dev/zero
SOURCE=/dev/urandom
#SOURCE=/dev/random

error() {
  echo "E: $*" >&2
}

die() {
  error "$*"
  exit 1
}

warn() {
  echo "W: $*"
}

info() {
  echo "I: $*"
}

usage() {
  exec 1>&2
cat << EOF
${0##*/} - a simple SD card testing tool, with small benchmarking features

  usage: ${0##*/} [opt] [opt] ... [blockdevice]

    opts:
      -B              display output of dd instances    ($BENCHMARK)
      -P              page size in Kilo Bytes           (${PAGE_SIZE_K}k)
      -W              write size in Kilo Bytes          (${WRITE_SIZE_K}k)
      -f              full write of blockdevice         ($FULLWRITE)
                      (page size == write size)
      --keep-data     keep data files                   ($KEEP_DATA_FILES)
      --keep-checksum keep data files                   ($KEEP_CHKSUM_FILES)
      --source        source device                     ($SOURCE)

  hints:
    * Usually you have a simple wrap around in address lanes on bad
      SD/MMC cards. This results in data written at the wrap around
      memory, erasing the beginning of the card.
    * If the MMC/SD card has a better FTL in place, a full write
      is needed as it tracks the written areas of the embedded flash.
      If a quick scan does not discover errors, use -f, if suspicous.

EOF
  exit 1
}

parse_arg() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -B ) BENCHMARK=yes ;;
      -W )
        WRITE_SIZE_K="$2"
        if [ -z "$WRITE_SIZE_K" ]; then
          error "wrong write size"
          usage
        fi
        shift
      ;;
      -P )
        PAGE_SIZE_K="$2"
        if [ -z "$PAGE_SIZE_K" ]; then
          error "wrong page size"
          usage
        fi
        shift
      ;;
      -f ) FULLWRITE=yes ;;
      --keep-data ) KEEP_DATA_FILES=yes ;;
      --keep-checksum ) KEEP_CHKSUM_FILES=yes ;;
      --source )
        SOURCE="$2"
        shift
      ;;
      -h | -* ) usage ;;
      * )
        DEV="$1"
        if [ ! -b "$1" ]; then
          error "device '$1' does not exist."
          usage
        fi
      ;;
      -* ) usage ;;
    esac
    shift
  done
  [ -n "$DEV" ] || usage
}
parse_arg "$@"

[ "$FULLWRITE" = yes ] && WRITE_SIZE_K="$PAGE_SIZE_K" || :

PAGE_SIZE_M=$((PAGE_SIZE_K / 1024))
WRITE_SIZE_M=$((WRITE_SIZE_K / 1024))

# get partinfo line, would fail
PARTINFO="$(grep "${DEV##*/}$" /proc/partitions )" || \
  die "could not get blockdevice info"
# get size in 1K blocks
SIZE_K="$(set $PARTINFO; echo $3)"
SIZE_M="$((SIZE_K / 1024))"
PAGE_FNAME_LEN="$(echo -n "$SIZE_M" | wc -c)"

if ! dd count=1 bs=1K if="$SOURCE" > /dev/null 2> /dev/null; then
  error "source '$SOURCE' not readable"
  usage
fi

info "device:      $DEV"
info "data source: $SOURCE"
info "page size:   ${PAGE_SIZE_K}k"
info "write size:  ${WRITE_SIZE_K}k"

# write test data
OFFSET=0
while [ "$OFFSET" -lt "$SIZE_M" ]; do
  #PAGE_FNAME="page_${DEV##*/}_$(printf "%0${PAGE_FNAME_LEN}dM" $OFFSET)"
  PAGE_FNAME="$(printf "%s_%0${PAGE_FNAME_LEN}dM_@_%0${PAGE_FNAME_LEN}dM" "${DEV##*/}" "$WRITE_SIZE_M" "$OFFSET")"
  PAGE_PIPE="$PAGE_FNAME.pipe"
  PAGE_CHKSUM="$PAGE_FNAME.$CHKSUM"

  info "write ${WRITE_SIZE_M}M at ${OFFSET}M to $DEV"

  rm -f "$PAGE_PIPE"
  mkfifo $PAGE_PIPE

  # start process to read from FIFO, write it ot file and chksum it
  if [ "$KEEP_DATA_FILES" = no ]; then
    < "$PAGE_PIPE" "$CHKSUM"
  else
    < "$PAGE_PIPE" tee "$PAGE_FNAME" | "$CHKSUM"
  fi > $PAGE_CHKSUM &

  # get PAGE_SIZE data, tee it to the FIFO and write it to the block device $DEV
  _STDERR="$(dd if="$SOURCE" bs=1K count="$WRITE_SIZE_K" status=none iflag=fullblock | \
    tee "$PAGE_PIPE" | \
    dd bs=1M seek="$OFFSET" of="$DEV" iflag=fullblock oflag=direct 2>&1)" || \
    die "writing page at offset $OFFSET failed"
  if [ "$BENCHMARK" = yes ]; then
    echo "$_STDERR" | sed -nre "/copied/ s/^/   / p"
  fi

  # at the end increment LOWER_OFFSET of page
  rm -f "$PAGE_PIPE"
  OFFSET=$((OFFSET + PAGE_SIZE_M))
done

echo

# verify test data
OFFSET=0
while [ "$OFFSET" -lt "$SIZE_M" ]; do
  #PAGE_FNAME="page_${DEV##*/}_$(printf "%0${PAGE_FNAME_LEN}dM" $OFFSET)"
  PAGE_FNAME="$(printf "%s_%0${PAGE_FNAME_LEN}dM_@_%0${PAGE_FNAME_LEN}dM" "${DEV##*/}" "$WRITE_SIZE_M" "$OFFSET")"
  PAGE_PIPE="$PAGE_FNAME.pipe"
  PAGE_CHKSUM="$PAGE_FNAME.$CHKSUM"

  info "read ${WRITE_SIZE_M}M at ${OFFSET}M from $DEV"
  _STDOUT="$(
    { # filter STDERR for xfer message
      3>&1 1>&2 2>&3 3>&- dd bs=1M skip="$OFFSET" count="$WRITE_SIZE_M" if="$DEV" | \
        if [ "$BENCHMARK" = yes ]; then
          sed -nre "/copied/ s/^/   / p"
        else
          cat > /dev/null
        fi
    } 3>&1 1>&2 2>&3 3>&- | \
      md5sum --check "$PAGE_CHKSUM"
  )" || _RS=$?
  # TODO: use $_RS for a better response

  echo "$_STDOUT" | sed 's/^-:/  /'

  # at the end increment LOWER_OFFSET of page
  rm -f "$PAGE_PIPE"
  [ "$KEEP_DATA_FILES" = yes ] || rm -f "$PAGE_CHKSUM"
  OFFSET=$((OFFSET + PAGE_SIZE_M))
done
