#!/usr/bin/env bash
# hygiene-master-kubeadm.sh — hygiène disque du control-plane kubeadm (PAS k3s).
# Cible : k3s-lyon-01 = nom historique. Runtime = kubeadm + containerd.
#
# Intouchable : /var/lib/etcd /etc/kubernetes /var/lib/kubelet/pki
#               manifests static pods, PVC, Longhorn, swap.img
#
# Défaut DRY_RUN=1. Application :
#   sudo DRY_RUN=0 NIVEAU=1 /usr/local/sbin/hygiene-master-kubeadm.sh
#   sudo DRY_RUN=0 NIVEAU=3 /usr/local/sbin/hygiene-master-kubeadm.sh
set -euo pipefail

DRY_RUN="${DRY_RUN:-1}"
NIVEAU="${NIVEAU:-1}"
JOURNAL_MAX="${JOURNAL_MAX:-200M}"
JOURNAL_AGE="${JOURNAL_AGE:-7d}"
TMP_DAYS="${TMP_DAYS:-10}"
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
if [[ -z "${CONTAINER_RUNTIME_ENDPOINT:-}" ]]; then
  if [[ -S /run/containerd/containerd.sock ]]; then
    CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
  elif [[ -S /var/run/containerd/containerd.sock ]]; then
    CONTAINER_RUNTIME_ENDPOINT=unix:///var/run/containerd/containerd.sock
  fi
fi
export KUBECONFIG CONTAINER_RUNTIME_ENDPOINT

HOST="$(hostname -s)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${LOG:-/var/log/disk-hygiene/master-${HOST}-${STAMP}.log}"
mkdir -p /var/log/disk-hygiene
exec > >(tee -a "$LOG")
exec 2>&1

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[DRY] %s\n' "$*"
  else
    printf '[RUN] %s\n' "$*"
    # shellcheck disable=SC2294
    eval "$@" || printf '[WARN] échec %s\n' "$*"
  fi
}

echo "HOST=${HOST} STAMP=${STAMP} DRY_RUN=${DRY_RUN} NIVEAU=${NIVEAU}"
echo "MODE=kubeadm-control-plane (pas k3s)"
command -v kubeadm >/dev/null && kubeadm version -o short 2>/dev/null || true
command -v kubectl >/dev/null && kubectl version --client -o yaml 2>/dev/null | awk '/gitVersion/ {print; exit}' || true

if [[ ! -d /etc/kubernetes/manifests ]]; then
  echo "ABORT: /etc/kubernetes/manifests absent — ce nœud n'est pas un control-plane kubeadm."
  exit 1
fi
if [[ ! -r "$KUBECONFIG" ]]; then
  echo "ABORT: ${KUBECONFIG} illisible."
  exit 1
fi

echo "-- garde-fous présents --"
ls -ld /etc/kubernetes /etc/kubernetes/manifests /var/lib/etcd 2>/dev/null || true
echo "INTERDIT: rm/truncate sur etcd, manifests, pki."

df -hP / | awk 'NR==2 {print "AVANT / used="$3" avail="$4" pct="$5}'
echo "-- poids typiques CP --"
du -sh /var/lib/containerd /var/lib/etcd /var/lib/kubelet /var/lib/snapd /snap \
       /var/log /var/cache/apt /swap.img 2>/dev/null || true

echo "== NIVEAU 1 : journal, apt, tmp, logs rotatés, cache VS Code =="
if command -v journalctl >/dev/null 2>&1; then
  run "journalctl --vacuum-size=${JOURNAL_MAX}"
  run "journalctl --vacuum-time=${JOURNAL_AGE}"
fi
if command -v apt-get >/dev/null 2>&1; then
  run "apt-get -y clean"
  run "apt-get -y autoclean"
fi
run "find /tmp /var/tmp -xdev -type f -mtime +${TMP_DAYS} -print -delete"
run "find /var/log -xdev -type f \\( -name '*.gz' -o -name '*.1' -o -name '*.old' \\) -mtime +7 -delete"
for d in /root /home/*; do
  [[ -d "$d/.vscode-server" ]] || continue
  run "find $d/.vscode-server/data/User/workspaceStorage -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
  run "rm -rf $d/.vscode-server/data/CachedExtensionVSIXs"
done

echo "== SNAP (mesure seule — pas de snap remove automatique) =="
if command -v snap >/dev/null 2>&1; then
  snap list 2>/dev/null || true
  du -sh /snap /var/lib/snapd 2>/dev/null || true
  echo "Revue manuelle: snap list puis snap remove <paquet> si hors cluster (lxd, vieux core)."
fi

if (( NIVEAU >= 2 )); then
  echo "== NIVEAU 2 : truncate logs runtime trop gros + pods Failed/Evicted =="
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    run "truncate -s 100M -- '$f'"
  done < <(find /var/lib/containerd /var/log/pods /var/lib/kubelet -type f -name '*.log' -size +100M 2>/dev/null || true)
  if command -v kubectl >/dev/null 2>&1; then
    run "kubectl --kubeconfig=${KUBECONFIG} delete pods -A --field-selector=status.phase=Failed --ignore-not-found=true"
    run "kubectl --kubeconfig=${KUBECONFIG} get pods -A --no-headers | awk '\$4==\"Evicted\" {print \$1,\$2}' | while read ns name; do kubectl --kubeconfig=${KUBECONFIG} delete pod -n \"\$ns\" \"\$name\" --ignore-not-found=true; done"
  fi
fi

if (( NIVEAU >= 3 )); then
  echo "== NIVEAU 3 : prune images NON utilisées seulement =="
  echo "crictl rmi --prune ne retire PAS kube-apiserver/etcd/pause s'ils ont un conteneur running."
  if command -v crictl >/dev/null 2>&1; then
    crictl --runtime-endpoint "$CONTAINER_RUNTIME_ENDPOINT" images || true
    crictl --runtime-endpoint "$CONTAINER_RUNTIME_ENDPOINT" ps || true
    run "crictl --runtime-endpoint ${CONTAINER_RUNTIME_ENDPOINT} rmi --prune"
  fi
  if command -v ctr >/dev/null 2>&1; then
    run "ctr -n k8s.io snapshots prune"
    run "ctr -n k8s.io content prune references || true"
  fi
  echo "NIVEAU 3 master : pas de touch etcd, pas de kubelet restart, pas de Longhorn."
fi

df -hP / | awk 'NR==2 {print "APRES / used="$3" avail="$4" pct="$5}'
echo "LOG=${LOG} FIN_MASTER"
echo "Contrôle cluster : kubectl get --raw /readyz?verbose && kubectl get nodes"
