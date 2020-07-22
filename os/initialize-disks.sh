#!/bin/bash
initialize_disk() {
  local disk="${1}"
  local to_label="${2}"
  local label="$(e2label "${disk}")"
  if [[ "$label" != "$to_label" ]]
  then
    wipefs -af "${disk}"
    mkfs.ext4 -L "${to_label}" "${disk}"
  fi
}

slow1="$(ls -1 /dev/disk/by-id/ata-WDC_*|head -n 1)"
slow2="$(ls -1 /dev/disk/by-id/ata-WDC_*|tail -n 1)"
fast="$(ls -1 /dev/disk/by-id/ata-CT*|head -n 1)"
locl="$(ls -1 /dev/disk/by-id/ata-CT*|tail -n 1)"

if [[ "${fast}" == "${locl}" ]]
then
  echo "No separate fast and locl"
  exit 1
fi

initialize_disk "$locl" "local"

mkdir -p /dev/disk/ceph
ln -s "${slow1}" /dev/disk/slow1
ln -s "${slow2}" /dev/disk/slow2
ln -s "${fast}" /dev/disk/fast
