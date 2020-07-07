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

initialize_disk "/dev/sda" "slow1"
initialize_disk "/dev/sdb" "slow2"
initialize_disk "/dev/sdc" "fast"
initialize_disk "/dev/sdd" "local"
