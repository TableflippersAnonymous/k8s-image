FROM ubuntu:20.04 AS opts

ENV KUBE_VERSION 1.18.6
ENV CRIO_VERSION 1.18.3
ENV COREDNS_VERSION 1.7.0
ENV KERNEL_VERSION 5.4.0-37-generic
ENV IMAGE_VERSION 1.0.3
ENV DEBIAN_FRONTEND noninteractive
ENV TZ UTC

RUN env | egrep -v '^(PATH|HOSTNAME|TERM|HOME)' > /etc/image.env

FROM opts AS core

RUN rm -f /run/systemd/container

RUN apt-get update && apt-get upgrade -y
RUN yes | unminimize

FROM core AS downloads

RUN apt-get install -y wget
RUN wget https://github.com/coredns/coredns/releases/download/v${COREDNS_VERSION}/coredns_${COREDNS_VERSION}_linux_amd64.tgz
RUN wget https://github.com/cri-o/cri-o/releases/download/v${CRIO_VERSION}/crio-v${CRIO_VERSION}.tar.gz
RUN wget https://dl.k8s.io/v${KUBE_VERSION}/kubernetes-node-linux-amd64.tar.gz

FROM core AS base

RUN apt-mark hold grub-pc
RUN apt-get install -y linux-image-${KERNEL_VERSION} linux-headers-${KERNEL_VERSION} live-boot systemd wget netplan.io ntp gnupg2 make squashfs-tools openssh-server iputils-ping htop vim pciutils lshw less iptables ntpdate ipmitool lvm2 curl

COPY --from=downloads coredns_${COREDNS_VERSION}_linux_amd64.tgz .
RUN tar -xpf coredns_${COREDNS_VERSION}_linux_amd64.tgz && \
  mv coredns /usr/bin/ && \
  chmod +x /usr/bin/coredns && \
  rm -rf coredns_${COREDNS_VERSION}_linux_amd64.tgz

RUN echo "deb http://pkg.scaleft.com/deb linux main" | tee -a /etc/apt/sources.list
RUN curl -C - https://dist.scaleft.com/pki/scaleft_deb_key.asc | apt-key add -
RUN echo "deb https://dl.bintray.com/falcosecurity/deb stable main" | tee -a /etc/apt/sources.list.d/falcosecurity.list
RUN curl -s https://falco.org/repo/falcosecurity-3672BA8F.asc | apt-key add -

RUN apt-get update
RUN apt-get install -y falco

COPY secrets/enrollment.token /var/lib/sftd/enrollment.token
RUN mkdir -p /etc/sftd && touch /etc/sftd/disable-autostart
RUN apt-get install -y scaleft-server-tools
RUN sed -i -r 's/^(After=.*)$/\1 initialize-hostname.service/' /etc/systemd/system/sftd.service
RUN rm -f /etc/sftd/disable-autostart

COPY os/initramfs.conf /etc/initramfs-tools/initramfs.conf
COPY os/fstab /etc/fstab
COPY os/hosts /etc/hosts
COPY os/ntp.conf /etc/ntp.conf
COPY os/coredns.conf /etc/coredns.conf
COPY os/coredns.service /usr/lib/systemd/system/
COPY os/resolv.conf /etc/resolv.conf
COPY os/netplan.yaml /etc/netplan/config.yaml
COPY os/initialize-disks.sh /usr/local/sbin/initialize-disks.sh
COPY os/initialize-hostname.sh /usr/local/sbin/initialize-hostname.sh
RUN chmod +x /usr/local/sbin/initialize-disks.sh /usr/local/sbin/initialize-hostname.sh
COPY os/initialize-disks.service /usr/lib/systemd/system
COPY os/initialize-hostname.service /usr/lib/systemd/system
COPY os/systemd.preset /usr/lib/systemd/system-preset/00-tblflp.preset
COPY os/sshd_config /etc/ssh/sshd_config
COPY os/authorized_keys /root/.ssh/authorized_keys
COPY os/ntpd.service /usr/lib/systemd/system
COPY os/ntpdate.service /usr/lib/systemd/system
RUN chmod 400 /root/.ssh/authorized_keys && chown root /root/.ssh/authorized_keys
COPY secrets/shadow /etc/shadow
RUN mkdir -p /var/log/ntpstats && chown 101:101 /var/log/ntpstats

RUN update-initramfs -u
RUN systemctl enable ntpd ntpdate coredns initialize-disks initialize-hostname ssh dm-event
RUN systemctl disable ntp

FROM base AS node

RUN mkdir /mnt/ceph /mnt/slow1 /mnt/slow2 /mnt/fast /mnt/local /mnt/local/crio /mnt/local/containers /mnt/local/log /mnt/local/log/pods

# CRI-O

COPY --from=downloads crio-v${CRIO_VERSION}.tar.gz .
RUN tar -xpf crio-v${CRIO_VERSION}.tar.gz && \
  ( cd crio-v${CRIO_VERSION} && \
    make install ) && \
  rm -rf crio-v${CRIO_VERSION}/ crio-v${CRIO_VERSION}.tar.gz
COPY worker/99-cri.conf /etc/sysctl.d/99-cri.conf
COPY worker/crio.conf /etc/crio/crio.conf
COPY worker/storage.conf /etc/containers/storage.conf
RUN rm -f /usr/local/lib/systemd/system/crio.service
COPY worker/crio.service /usr/lib/systemd/system/crio.service
RUN systemctl enable crio

# KUBERNETES

COPY --from=downloads kubernetes-node-linux-amd64.tar.gz .
RUN tar -xpf kubernetes-node-linux-amd64.tar.gz && \
  mv kubernetes/node/bin/kubelet /usr/bin/ && \
  rm -rf kubernetes kubernetes-node-linux-amd64.tar.gz

COPY worker/kubelet.yaml /etc/kubelet.yaml
COPY worker/kubelet.service /usr/lib/systemd/system/
RUN mkdir /etc/kubelet /etc/kubelet/pki /etc/kubelet/static
COPY secrets/bootstrap.yaml /etc/kubelet/bootstrap.yaml
COPY secrets/pki/ca.crt /etc/pki/k8sca.crt
RUN systemctl enable kubelet

FROM node AS leader

COPY secrets/tokens /etc/kubernetes/tokens
COPY secrets/pki /etc/kubernetes/pki
COPY secrets/controller.yaml /etc/kubernetes/controller.kubeconfig
COPY secrets/scheduler.yaml /etc/kubernetes/scheduler.kubeconfig

FROM leader AS k8s-01

COPY leaders/k8s-01/kube-apiserver.yaml /etc/kubelet/static/
COPY leaders/k8s-01/kube-controller-manager.yaml /etc/kubelet/static/
COPY leaders/k8s-01/kube-scheduler.yaml /etc/kubelet/static/
COPY leaders/k8s-01/etcd.yaml /etc/kubelet/static/

FROM leader AS k8s-02

COPY leaders/k8s-02/kube-apiserver.yaml /etc/kubelet/static/
COPY leaders/k8s-02/kube-controller-manager.yaml /etc/kubelet/static/
COPY leaders/k8s-02/kube-scheduler.yaml /etc/kubelet/static/
COPY leaders/k8s-02/etcd.yaml /etc/kubelet/static/

FROM leader AS k8s-03

COPY leaders/k8s-03/kube-apiserver.yaml /etc/kubelet/static/
COPY leaders/k8s-03/kube-controller-manager.yaml /etc/kubelet/static/
COPY leaders/k8s-03/kube-scheduler.yaml /etc/kubelet/static/
COPY leaders/k8s-03/etcd.yaml /etc/kubelet/static/

FROM core AS ipxe

RUN apt-get install -y git gcc binutils make perl mtools liblzma-dev mkisofs syslinux
RUN git clone git://git.ipxe.org/ipxe.git
COPY pxe/boot.ipxe ipxe/src/boot.ipxe
RUN sed -ri "s/IMAGE_VERSION/${KUBE_VERSION}-${IMAGE_VERSION}/g" ipxe/src/boot.ipxe
RUN cd ipxe/src && make -j16 bin/undionly.kpxe EMBED=boot.ipxe

FROM core AS builder

RUN apt-get install -y squashfs-tools

RUN mkdir /tftp /roots /images

COPY --from=node / /roots/node
COPY --from=k8s-01 / /roots/k8s-01
COPY --from=k8s-02 / /roots/k8s-02
COPY --from=k8s-03 / /roots/k8s-03

RUN cp /roots/node/boot/initrd.img-${KERNEL_VERSION} /tftp/initrd.img-${KUBE_VERSION}-${IMAGE_VERSION}
RUN cp /roots/node/boot/vmlinuz-${KERNEL_VERSION} /tftp/vmlinuz-${KUBE_VERSION}-${IMAGE_VERSION}
RUN cp /roots/node/boot/config-${KERNEL_VERSION} /tftp/config-${KUBE_VERSION}-${IMAGE_VERSION}
RUN cp /roots/node/boot/System.map-${KERNEL_VERSION} /tftp/System.map-${KUBE_VERSION}-${IMAGE_VERSION}
RUN rm -rf /roots/*/boot

RUN mksquashfs /roots/node /images/node-${KUBE_VERSION}-${IMAGE_VERSION}.squashfs -comp lzo
RUN mksquashfs /roots/k8s-01 /images/k8s-01-${KUBE_VERSION}-${IMAGE_VERSION}.squashfs -comp lzo
RUN mksquashfs /roots/k8s-02 /images/k8s-02-${KUBE_VERSION}-${IMAGE_VERSION}.squashfs -comp lzo
RUN mksquashfs /roots/k8s-03 /images/k8s-03-${KUBE_VERSION}-${IMAGE_VERSION}.squashfs -comp lzo

COPY --from=ipxe ipxe/src/bin/undionly.kpxe /tftp/boot-${KUBE_VERSION}-${IMAGE_VERSION}.kpxe
RUN tar -zcpf /images/tftp-${KUBE_VERSION}-${IMAGE_VERSION}.tgz -C /tftp .

RUN rm -rf /roots /tftp

CMD cp -v /images/* /volume/
