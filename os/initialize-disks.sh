#!/bin/bash
#
# Find this node's disks and give them stable names.
#
#   local   a Crucial (ata-CT*) SSD, ext4 LABEL=local, mounted at /mnt/local
#           by fstab.  CRI-O, kubelet and (on leaders) etcd live here.
#   slow1/2 the two WDC disks      -> /dev/disk/slow1, /dev/disk/slow2
#   fast    the first other disk   -> /dev/disk/fast
#
# The only destructive thing this script does is create the local
# filesystem, and it will only do that on a disk that is completely BLANK:
# no filesystem, no partition table, no LVM or other signature, nothing
# holding it.  It never wipes anything.  If it cannot identify the local
# disk unambiguously it refuses and exits non-zero, rather than guessing --
# a guess here has, in the past, pointed at a Ceph OSD.
#
# To put a previously used disk into service as local, wipe it by hand
# (wipefs -a /dev/sdX) and reboot.

set -u
shopt -s nullglob

BY_ID="${DISK_BY_ID:-/dev/disk/by-id}"
LINK_DIR="${DISK_LINK_DIR:-/dev/disk}"

log() {
  echo "initialize-disks: $*" >&2
}

fatal() {
  log "$*"
  echo "initialize-disks: $*" > /dev/kmsg 2>/dev/null || true
  exit 1
}

# Whole disks (not partitions) matching a by-id pattern, sorted.
disks() {
  local p
  for p in "${BY_ID}"/$1; do
    [[ "$p" == *-part* ]] && continue
    echo "$p"
  done | sort
}

probe() {
  blkid -p -o export "$1" 2>/dev/null
}

has_label_local() {
  local out
  out="$(probe "$1")"
  grep -qx 'TYPE=ext4' <<<"$out" && grep -qx 'LABEL=local' <<<"$out"
}

# Blank means: low-level probe finds no filesystem or partition table, the
# kernel sees no partitions, and nothing (LVM, md, dm) holds the device.
blank() {
  local dev name
  dev="$(readlink -f "$1")"
  name="${dev##*/}"
  probe "$1" | grep -qE '^(TYPE|PTTYPE)=' && return 1
  [[ -n "$(ls -A "/sys/class/block/${name}/holders" 2>/dev/null)" ]] && return 1
  [[ "$(lsblk -nro NAME "$dev" 2>/dev/null | wc -l)" -gt 1 ]] && return 1
  return 0
}

describe() {
  local d
  for d in "$@"; do
    log "  ${d##*/} -> $(readlink -f "$d"): $(probe "$d" | grep -E '^(TYPE|PTTYPE|LABEL)=' | tr '\n' ' ')"
  done
}

# --- local -----------------------------------------------------------------

mapfile -t ct < <(disks 'ata-CT*')
labelled=()
blanks=()
for d in "${ct[@]}"; do
  if has_label_local "$d"; then
    labelled+=("$d")
  elif blank "$d"; then
    blanks+=("$d")
  fi
done

if [[ "${#labelled[@]}" -eq 1 ]]; then
  locl="${labelled[0]}"
  log "local is ${locl##*/}"
elif [[ "${#labelled[@]}" -gt 1 ]]; then
  log "candidates:"; describe "${ct[@]}"
  fatal "more than one disk is labelled local; refusing to choose"
elif [[ "${#blanks[@]}" -eq 1 ]]; then
  locl="${blanks[0]}"
  log "no disk is labelled local; formatting blank ${locl##*/}"
  mkfs.ext4 -q -L local "$locl" || fatal "mkfs.ext4 failed on ${locl##*/}"
  # Make sure /dev/disk/by-label/local exists before fstab looks for it.
  # Bounded: --settle waits on udevd, and must never be able to hang boot.
  timeout 30 udevadm trigger --action=change --settle "$(readlink -f "$locl")" 2>/dev/null || true
else
  log "candidates:"; describe "${ct[@]}"
  fatal "no disk is labelled local and ${#blanks[@]} blank Crucial disks are present (need exactly 1); refusing to format anything"
fi

# --- ceph disk names ---------------------------------------------------------
#
# Not needed to boot, so problems here are reported but not fatal.

mapfile -t wdc < <(disks 'ata-WDC_*')
if [[ "${#wdc[@]}" -ge 1 ]]; then
  ln -sfn "${wdc[0]}" "${LINK_DIR}/slow1"
  ln -sfn "${wdc[${#wdc[@]}-1]}" "${LINK_DIR}/slow2"
  [[ "${#wdc[@]}" -eq 2 ]] || log "expected 2 WDC disks, found ${#wdc[@]}"
else
  log "no WDC disks found; slow1/slow2 not created"
fi

fast=""
for d in $(disks 'ata-*'); do
  [[ "$d" == *WDC_* || "$d" == "$locl" ]] && continue
  fast="$d"
  break
done
if [[ -n "$fast" ]]; then
  ln -sfn "$fast" "${LINK_DIR}/fast"
else
  log "no disk available for fast"
fi

exit 0
