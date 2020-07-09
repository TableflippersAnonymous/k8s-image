#!/bin/bash
for e in $(tr "\000" "\n" < /proc/1/environ); do
  eval "export $e"
done

nodenum=$(echo $pxeip | awk -F. '{print $4}')

host=$(printf "k8s-%02d" $nodenum)

node=$(printf "k8s-%02d.as53546.tblflp.zone" $nodenum)

hostnamectl set-hostname $node
cat <<EOF >/etc/nodeinfo.env
HOST=${host}
FQDN=${node}
ADMIN_IP=10.199.11.${nodenum}
ADMIN_HOST=${host}-admin.as53546.tblflp.zone
PUBLIC_IP=144.86.176.${nodenum}
PUBLIC_HOST=${host}-public.as53546.tblflp.zone
PRIVATE_IP=10.199.14.${nodenum}
PRIVATE_HOST=${host}-private.as53546.tblflp.zone
PXE_IP=${pxeip}
BOOT_SERVER=10.199.14.201
LB_IP=10.199.15.${nodenum}
LB_HOST=${host}-lb.as53546.tblflp.zone
STORAGE_IP=10.199.16.${nodenum}
STORAGE_HOST=${host}-storage.as53546.tblflp.zone
CLUSTER_IP=10.199.17.${nodenum}
CLUSTER_HOST=${host}-cluster.as53546.tblflp.zone
EOF
