#!/bin/bash
mkdir secrets
cd secrets

TOKEN_BOOTSTRAP="$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')"
TOKEN_CONTROLLER_MANAGER="$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')"
TOKEN_SCHEDULER="$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')"
TOKEN_ADMIN="$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')"

cat >tokens <<EOF
${TOKEN_BOOTSTRAP},kubelet-bootstrap,10001,"system:bootstrappers"
${TOKEN_CONTROLLER_MANAGER},system:kube-controller-manager,10002,"system:kube-controller-manager"
${TOKEN_SCHEDULER},system:kube-scheduler,10003,"system:kube-scheduler"
${TOKEN_ADMIN},admin,10004,"system:masters"
EOF

cat >bootstrap.yaml <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /etc/pki/k8sca.crt
    server: https://k8s-masters.as53546.tblflp.zone
  name: tblflp
contexts:
- context:
    cluster: tblflp
    user: bootstrap
  name: tblflp
current-context: tblflp
kind: Config
preferences: {}
users:
- name: bootstrap
  user:
    token: ${TOKEN_BOOTSTRAP}
EOF

cat >controller.yaml <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/pki/ca.crt
    server: https://k8s-masters.as53546.tblflp.zone
  name: tblflp
contexts:
- context:
    cluster: tblflp
    user: controller
  name: tblflp
current-context: tblflp
kind: Config
preferences: {}
users:
- name: controller
  user:
    token: ${TOKEN_CONTROLLER_MANAGER}
EOF

cat >scheduler.yaml <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/pki/ca.crt
    server: https://k8s-masters.as53546.tblflp.zone
  name: tblflp
contexts:
- context:
    cluster: tblflp
    user: scheduler
  name: tblflp
current-context: tblflp
kind: Config
preferences: {}
users:
- name: scheduler
  user:
    token: ${TOKEN_SCHEDULER}
EOF

cat >shadow <<EOF
root:*:18449:0:99999:7:::
daemon:*:18419:0:99999:7:::
bin:*:18419:0:99999:7:::
sys:*:18419:0:99999:7:::
sync:*:18419:0:99999:7:::
games:*:18419:0:99999:7:::
man:*:18419:0:99999:7:::
lp:*:18419:0:99999:7:::
mail:*:18419:0:99999:7:::
news:*:18419:0:99999:7:::
uucp:*:18419:0:99999:7:::
proxy:*:18419:0:99999:7:::
www-data:*:18419:0:99999:7:::
backup:*:18419:0:99999:7:::
list:*:18419:0:99999:7:::
irc:*:18419:0:99999:7:::
gnats:*:18419:0:99999:7:::
nobody:*:18419:0:99999:7:::
_apt:*:18419:0:99999:7:::
messagebus:*:18448:0:99999:7:::
uuidd:*:18448:0:99999:7:::
ntp:*:18448:0:99999:7:::
systemd-network:*:18448:0:99999:7:::
systemd-resolve:*:18448:0:99999:7:::
EOF

mkdir pki
cd pki
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=k8s-masters.as53546.tblflp.zone" -days 10000 -out ca.crt
openssl genrsa -out server.key 2048
cat >csr.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = US
ST = NC
L = Raleigh
O = Legion, Inc.
OU = AS53546
CN = k8s-masters.as53546.tblflp.zone

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster
DNS.5 = kubernetes.default.svc.cluster.local
DNS.6 = k8s-masters.as53546.tblflp.zone
DNS.7 = k8s-masters
IP.1 = 10.199.15.200
IP.2 = 10.195.1.1
IP.3 = 10.195.0.1

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

openssl req -new -key server.key -out server.csr -config csr.conf
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 10000 -extensions v3_ext -extfile csr.conf

## EXTENSION API SERVER
openssl genrsa -out ext-ca.key 2048
openssl req -x509 -new -nodes -key ext-ca.key -subj "/CN=front-proxy-ca" -days 10000 -out ext-ca.crt
openssl genrsa -out ext-proxy.key 2048
cat >ext-csr.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = US
ST = NC
L = Raleigh
O = Legion, Inc.
OU = AS53546
CN = front-proxy-client

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = front-proxy-client
DNS.2 = kubernetes
DNS.3 = kubernetes.default
DNS.4 = kubernetes.default.svc
DNS.5 = kubernetes.default.svc.cluster
DNS.6 = kubernetes.default.svc.cluster.local
DNS.7 = k8s-masters.as53546.tblflp.zone
DNS.8 = k8s-masters
IP.1 = 10.199.15.200
IP.2 = 10.195.1.1
IP.3 = 10.195.0.1

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF
openssl req -new -key ext-proxy.key -out ext-proxy.csr -config ext-csr.conf
openssl x509 -req -in ext-proxy.csr -CA ext-ca.crt -CAkey ext-ca.key -CAcreateserial -out ext-proxy.crt -days 10000 -extensions v3_ext -extfile ext-csr.conf
