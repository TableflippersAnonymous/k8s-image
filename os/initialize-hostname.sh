#!/bin/bash
#
# Derive this machine's identity from its SMBIOS UUID and write
# /etc/nodeinfo.env.  Runs before networking; nothing here may touch the
# network, since the addresses it emits are what bring the network up.

set -u

fatal() {
  echo "initialize-hostname: $*" >&2
  echo "initialize-hostname: $*" > /dev/kmsg 2>/dev/null || true
  exit 1
}

uuid="$(tr 'A-F' 'a-f' < /sys/class/dmi/id/product_uuid 2>/dev/null | tr -d '[:space:]')"
[[ -n "$uuid" ]] || fatal "cannot read /sys/class/dmi/id/product_uuid"

nodenum=""
while read -r table_uuid table_num _; do
  [[ "$table_uuid" =~ ^# ]] && continue
  [[ -n "$table_num" ]] || continue
  if [[ "$(tr 'A-F' 'a-f' <<<"$table_uuid")" == "$uuid" ]]; then
    nodenum="$table_num"
    break
  fi
done < /etc/nodes.conf

[[ -n "$nodenum" ]] || fatal "unknown machine: product_uuid $uuid is not in /etc/nodes.conf"

host="$(printf "k8s-%02d" "$nodenum")"
node="${host}.as53546.tblflp.zone"

echo "$node" > /etc/hostname
hostname "$node"

cat <<EOF >/etc/nodeinfo.env
NODE_NUM=${nodenum}
HOST=${host}
FQDN=${node}
ADMIN_IP=10.199.11.${nodenum}
ADMIN_HOST=${host}-admin.as53546.tblflp.zone
PRIVATE_IP=10.199.14.${nodenum}
PRIVATE_HOST=${host}-private.as53546.tblflp.zone
PUBLIC_IP=144.86.176.${nodenum}
PUBLIC_IP6=2602:f3ad::${nodenum}
PUBLIC_HOST=${host}-public.as53546.tblflp.zone
CLUSTER_IP=10.199.17.${nodenum}
CLUSTER_HOST=${host}-cluster.as53546.tblflp.zone
LB_IP=10.199.15.200
LB_HOST=k8s-masters.as53546.tblflp.zone
BOOT_SERVER=10.199.14.201
EOF
