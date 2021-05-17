#!/bin/bash

for pod in etcd kube-apiserver kube-controller-manager kube-scheduler
do
  sed -r "s/\\\$NODE_NAME/$NODE_NAME/g" "/tmp/${pod}.yaml" | \
    sed -r "s/\\\$ETCD_VERSION/$ETCD_VERSION/g" | \
    sed -r "s/\\\$KUBE_VERSION/$KUBE_VERSION/g" | \
    sed -r "s/\\\$LB_IP/$LB_IP/g" | \
    sed -r "s/\\\$PRIVATE_IP/$PRIVATE_IP/g" > "/etc/kubelet/static/${pod}.yaml"
done
