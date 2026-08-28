#!/usr/bin/env bash
# audit-disque.sh — lecture seule. Inventaire d'occupation pour nœud Linux + Kubernetes.
# Usage : sudo ./audit-disque.sh [rapport.out]
# Sortie : stdout + fichier horodaté si un chemin est fourni, sinon ./audit-disque-<host>-<date>.txt
set -euo pipefail

HOST="$(hostname -s)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${1:-./audit-disque-${HOST}-${STAMP}.txt}"
THRESH_WARN="${THRESH_WARN:-70}"
THRESH_ALERT="${THRESH_ALERT:-80}"
THRESH_CRIT="${THRESH_CRIT:-90}"
if [[ -z "${CONTAINER_RUNTIME_ENDPOINT:-}" ]]; then
  if [[ -S /run/containerd/containerd.sock ]]; then
    export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
  elif [[ -S /var/run/containerd/containerd.sock ]]; then
    export CONTAINER_RUNTIME_ENDPOINT=unix:///var/run/containerd/containerd.sock
  fi
fi
if [[ -z "${KUBECONFIG:-}" && -r /etc/kubernetes/admin.conf ]]; then
  export KUBECONFIG=/etc/kubernetes/admin.conf
fi

exec > >(tee -a "$OUT")
exec 2>&1

hr() { printf '\n======== %s ========\n' "$1"; }
cmd() {
  printf '\n$ %s\n' "$*"
  # shellcheck disable=SC2294
  eval "$@" || printf '[WARN] commande en échec (code %s)\n' "$?"
}

hr "AUDIT DISQUE ${HOST} ${STAMP}"
echo "Nœud          : ${HOST}"
echo "Kernel        : $(uname -r)"
echo "OS            : $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-inconnu}")"
echo "Date UTC      : ${STAMP}"
echo "Seuils %      : WARN=${THRESH_WARN} ALERT=${THRESH_ALERT} CRIT=${THRESH_CRIT}"

hr "FILESYSTEMS (espace)"
cmd "df -hT -x tmpfs -x devtmpfs -x overlay -x squashfs"

hr "FILESYSTEMS (inodes)"
cmd "df -hi -x tmpfs -x devtmpfs -x overlay -x squashfs"

hr "SEUILS RACINE"
root_pct="$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')"
echo "Occupation / = ${root_pct}%"
if   (( root_pct >= THRESH_CRIT )); then echo "STATUT=CRITIQUE"
elif (( root_pct >= THRESH_ALERT )); then echo "STATUT=ALERTE"
elif (( root_pct >= THRESH_WARN ));  then echo "STATUT=WARNING"
else echo "STATUT=OK"
fi

hr "TOP REPERTOIRES / (profondeur 2, peut prendre 1-3 min)"
cmd "du -xhd2 / 2>/dev/null | sort -hr | head -n 40"

hr "VAR LIB (runtime)"
for d in /var/lib/containerd /var/lib/docker /var/lib/kubelet /var/lib/etcd \
         /var/lib/longhorn /var/lib/snapd /snap \
         /var/lib/zabbix /var/lib/grafana /var/lib/pgsql /var/lib/mysql \
         /var/log /var/tmp /tmp /var/cache /home; do
  if [[ -d "$d" ]]; then
    du -xh -d0 "$d" 2>/dev/null || true
  fi
done

hr "JOURNALD"
if command -v journalctl >/dev/null 2>&1; then
  cmd "journalctl --disk-usage"
else
  echo "journalctl absent"
fi

hr "GROS FICHIERS > 100M (hors /proc /sys /dev overlay)"
cmd "find / -xdev -type f -size +100M -printf '%s\t%p\n' 2>/dev/null | sort -nr | head -n 30 | awk '{printf \"%12.1f MiB  %s\\n\", \$1/1024/1024, \$2}'"

hr "LOGS > 50M"
cmd "find /var/log /var/lib/docker /var/lib/containerd /var/log/pods /var/lib/kubelet -type f \\( -name '*.log' -o -name '*.log.*' \\) -size +50M -printf '%s\t%p\n' 2>/dev/null | sort -nr | head -n 30 | awk '{printf \"%12.1f MiB  %s\\n\", \$1/1024/1024, \$2}'"

hr "CACHE PAQUETS"
if command -v dnf >/dev/null 2>&1; then
  cmd "dnf -q clean expire-cache >/dev/null 2>&1 || true; du -sh /var/cache/dnf /var/cache/yum 2>/dev/null || true"
elif command -v apt-get >/dev/null 2>&1; then
  cmd "du -sh /var/cache/apt /var/cache/apt/archives 2>/dev/null || true"
fi

hr "NOYAUX INSTALLES"
cmd "ls -1 /boot/vmlinuz-* 2>/dev/null || true"
if command -v rpm >/dev/null 2>&1; then
  cmd "rpm -q kernel kernel-core 2>/dev/null || true"
fi

hr "KUBERNETES / CRI"
if command -v crictl >/dev/null 2>&1; then
  echo "CRI endpoint=${CONTAINER_RUNTIME_ENDPOINT:-unset}"
  cmd "crictl info 2>/dev/null | head -n 20 || true"
  cmd "crictl images 2>/dev/null || true"
  cmd "crictl ps -a 2>/dev/null | head -n 50 || true"
  echo
  echo "-- compte images / snapshots --"
  cmd "crictl images -q 2>/dev/null | wc -l || true"
  cmd "ctr -n k8s.io snapshots ls 2>/dev/null | awk 'NR>1 {c[\$NF]++} END {for (k in c) print k, c[k]}' || true"
fi
if command -v snap >/dev/null 2>&1; then
  hr "SNAP"
  cmd "snap list 2>/dev/null || true"
  cmd "du -sh /snap /var/lib/snapd 2>/dev/null || true"
fi
if [[ -d /var/lib/longhorn ]]; then
  hr "LONGHORN"
  cmd "du -xh -d1 /var/lib/longhorn 2>/dev/null | sort -hr | head -n 15"
fi
if command -v docker >/dev/null 2>&1; then
  hr "DOCKER (legacy)"
  cmd "docker system df 2>/dev/null || true"
fi

if command -v kubectl >/dev/null 2>&1; then
  if [[ -n "${KUBECONFIG:-}" && -r "${KUBECONFIG}" ]]; then
    cmd "kubectl get nodes -o wide 2>/dev/null || true"
    cmd "kubectl get pods -A --field-selector=status.phase=Failed 2>/dev/null || true"
    cmd "kubectl get pods -A | awk '\$4 ~ /Evicted|Error|CrashLoop|Completed/ {print}' 2>/dev/null || true"
    cmd "kubectl get --raw /metrics 2>/dev/null | grep -E 'kubelet_volume_stats_used_bytes|node_filesystem' | head || true"
  else
    echo "kubeconfig non lisible depuis ce compte"
  fi
fi

hr "ZABBIX / GRAFANA (si locaux)"
for d in /var/lib/zabbix /usr/share/zabbix /var/log/zabbix \
         /var/lib/grafana /var/log/grafana /var/lib/pgsql /var/lib/mysql; do
  [[ -d "$d" ]] && du -xh -d1 "$d" 2>/dev/null | sort -hr | head -n 15
done

hr "RESUME ACTIONNABLE"
echo "1. Relire STATUT ci-dessus."
echo "2. Croiser TOP REPERTOIRES + GROS FICHIERS."
echo "3. Si containerd/snapshots dominent : NIVEAU 1 puis NIVEAU 3 (crictl rmi --prune + ctr snapshots prune)."
echo "4. Ne jamais rm -rf /var/lib/{containerd,docker,kubelet,etcd}."
echo "5. Rapport : $OUT"
echo "FIN_AUDIT"
