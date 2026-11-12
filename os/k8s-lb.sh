#!/bin/bash
#
# IPVS director for the kube-apiserver VIP.
#
# 10.199.15.200/32 is routed to the nodes and held locally on the k8s-lb dummy
# interface, so a packet for the VIP that lands on any node is intercepted here
# rather than hairpinning through the router.  IPVS then NATs it to one of the
# three control-plane nodes.
#
# Forwarding is masquerade rather than direct-routing because the real servers
# answer on their own private addresses: without SNAT the reply from a remote
# master would reach the client from the wrong source address.  The rule is
# scoped to the private bond, so when IPVS happens to pick the local master the
# packet stays unmangled and the apiserver still sees the real client.
#
# Plain ipvsadm has no health checking, so the monitor loop below polls each
# master and parks a failed one at weight 0.

set -u

VIP=10.199.15.200
# Clients reach the VIP on 443 -- the kubeconfigs say https://k8s-masters
# with no port -- and some on 6443.  Both map onto the apiservers' 6443;
# IPVS masquerade translates the port.
VIP_PORTS="443 6443"
PORT=6443
MASTERS="10.199.14.1 10.199.14.2 10.199.14.3"
INTERVAL=5

log() { echo "k8s-lb: $*"; }

# Create any virtual service or destination that is missing.  Run at setup
# and on every monitor pass: kube-proxy in IPVS mode deletes virtual
# services it does not own unless they are in its ipvs.excludeCIDRs, and
# without this the VIP would vanish silently until the next reboot.
#
# Never "ipvsadm -C": that would flush kube-proxy's services too.
ensure_services() {
  local vport master created=0
  for vport in ${VIP_PORTS}; do
    if ! ipvsadm -Ln -t "${VIP}:${vport}" >/dev/null 2>&1; then
      ipvsadm -A -t "${VIP}:${vport}" -s rr && created=1
      [[ "${#state[@]}" -gt 0 ]] && \
        log "${VIP}:${vport} was missing and has been recreated -- exclude ${VIP} in the cluster service proxy (kube-router --excluded-cidrs / kube-proxy --ipvs-exclude-cidrs)"
    fi
    for master in ${MASTERS}; do
      # New destinations start parked; reconcile decides their weight.
      ipvsadm -a -t "${VIP}:${vport}" -r "${master}:${PORT}" -m -w 0 2>/dev/null && created=1
    done
  done
  # Forget cached weights so reconcile re-applies them to what was created.
  (( created )) && state=()
  return 0
}

setup() {
  modprobe ip_vs
  modprobe ip_vs_rr
  modprobe nf_conntrack

  # IPVS bypasses conntrack unless asked not to, and MASQUERADE needs it.
  sysctl -qw net.ipv4.vs.conntrack=1
  # Drop connections pinned to a destination that has gone away instead of
  # letting them hang until the client gives up.
  sysctl -qw net.ipv4.vs.expire_nodest_conn=1

  ensure_services

  for master in ${MASTERS}; do
    iptables -t nat -C POSTROUTING -o private -p tcp -d "${master}" \
      --dport "${PORT}" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o private -p tcp -d "${master}" \
      --dport "${PORT}" -j MASQUERADE
  done

  reconcile

  # modprobe is allowed to fail (the modules may be built in), so confirm the
  # table actually exists rather than reporting a working VIP that isn't.
  for vport in ${VIP_PORTS}; do
    ipvsadm -Ln -t "${VIP}:${vport}" >/dev/null 2>&1 || {
      log "failed to program IPVS for ${VIP}:${vport}; is ip_vs available?"
      exit 1
    }
  done
}

# A master counts as up if it answers /readyz at all.  Any HTTP status will
# do -- the point is that the apiserver is listening and serving, not that it
# likes our (absent) credentials.
healthy() {
  local code
  code="$(curl -sk -o /dev/null -m 2 -w '%{http_code}' \
    "https://${1}:${PORT}/readyz" 2>/dev/null)"
  [[ -n "$code" && "$code" != "000" ]]
}

reconcile() {
  local master vport want up=0
  for master in ${MASTERS}; do
    if healthy "$master"; then want=1; up=$((up + 1)); else want=0; fi
    if [[ "${state[$master]:-}" != "$want" ]]; then
      for vport in ${VIP_PORTS}; do
        ipvsadm -e -t "${VIP}:${vport}" -r "${master}:${PORT}" -m -w "$want"
      done
      log "${master} weight ${want}"
      state[$master]="$want"
    fi
  done
  if [[ "$up" -eq 0 && "${state[_up]:-}" != "0" ]]; then
    log "no apiserver is answering; ${VIP} is a black hole"
  fi
  state[_up]="$up"
}

declare -A state=()

case "${1:-monitor}" in
  setup)
    setup
    ;;
  monitor)
    while true; do
      sleep "${INTERVAL}"
      ensure_services
      reconcile
    done
    ;;
  *)
    echo "usage: ${0##*/} setup|monitor" >&2
    exit 1
    ;;
esac
