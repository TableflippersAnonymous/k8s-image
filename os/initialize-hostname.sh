#!/bin/bash
for e in $(tr "\000" "\n" < /proc/1/environ); do
  eval "export $e"
done

nodenum=$(echo $pxeip | awk -F. '{print $4}')

node=$(printf "k8s-%02d.as53546.tblflp.zone" $nodenum)

hostnamectl set-hostname $node
