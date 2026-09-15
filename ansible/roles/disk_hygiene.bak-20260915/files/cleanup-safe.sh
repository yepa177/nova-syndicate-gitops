#!/usr/bin/env bash
# cleanup-safe.sh — hygiène disque idempotente pour nœud Linux + K8s.
# Défaut : DRY_RUN=1 (aucune suppression). Forcer : DRY_RUN=0 sudo ./cleanup-safe.sh
# NIVEAU=1 journal+cache+tmp | NIVEAU=2 + logs conteneurs + pods Failed/Evicted | NIVEAU=3 + prune images (maintenance)
set -euo pipefail

# CLI / systemd / Ansible écrasent le fichier d'environnement.
_DRY_RUN="${DRY_RUN-}"
_NIVEAU="${NIVEAU-}"
_JOURNAL_MAX="${JOURNAL_MAX-}"
_JOURNAL_AGE="${JOURNAL_AGE-}"
_TMP_DAYS="${TMP_DAYS-}"
_CTR_LOG_MAX_MB="${CTR_LOG_MAX_MB-}"
_LOG="${LOG-}"
_KUBECONFIG="${KUBECONFIG-}"

ENV_FILE="${ENV_FILE:-/etc/default/disk-hygiene}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  . "$ENV_FILE"
  set +a
fi

DRY_RUN="${_DRY_RUN:-${DRY_RUN:-1}}"
NIVEAU="${_NIVEAU:-${NIVEAU:-1}}"
JOURNAL_MAX="${_JOURNAL_MAX:-${JOURNAL_MAX:-500M}}"
JOURNAL_AGE="${_JOURNAL_AGE:-${JOURNAL_AGE:-7d}}"
TMP_DAYS="${_TMP_DAYS:-${TMP_DAYS:-10}}"
CTR_LOG_MAX_MB="${_CTR_LOG_MAX_MB:-${CTR_LOG_MAX_MB:-100}}"
if [[ -z "${_KUBECONFIG}" && -z "${KUBECONFIG:-}" ]]; then
  KUBECONFIG=/etc/kubernetes/admin.conf
else
  KUBECONFIG="${_KUBECONFIG:-${KUBECONFIG}}"
fi
if [[ -z "${CONTAINER_RUNTIME_ENDPOINT:-}" ]]; then
  if [[ -S /run/containerd/containerd.sock ]]; then
    CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
  elif [[ -S /var/run/containerd/containerd.sock ]]; then
    CONTAINER_RUNTIME_ENDPOINT=unix:///var/run/containerd/containerd.sock
  fi
fi
export CONTAINER_RUNTIME_ENDPOINT KUBECONFIG
HOST="$(hostname -s)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${_LOG:-${LOG:-/var/log/disk-hygiene/cleanup-${HOST}-${STAMP}.log}}"
mkdir -p "$(dirname "$LOG")" /var/log/disk-hygiene 2>/dev/null || true

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
df -hP / | awk 'NR==2 {print "AVANT / used="$3" avail="$4" pct="$5}'

echo "== NIVEAU 1 : journal, caches, tmp =="
if command -v journalctl >/dev/null 2>&1; then
  run "journalctl --vacuum-size=${JOURNAL_MAX}"
  run "journalctl --vacuum-time=${JOURNAL_AGE}"
fi
if command -v dnf >/dev/null 2>&1; then
  run "dnf -y clean all"
elif command -v apt-get >/dev/null 2>&1; then
  run "apt-get -y clean"
  run "apt-get -y autoclean"
fi
run "find /tmp /var/tmp -xdev -type f -mtime +${TMP_DAYS} -print -delete"
run "find /var/crash /var/spool/abrt -xdev -type f -mtime +14 -print -delete 2>/dev/null || true"
run "find /var/log -xdev -type f \\( -name '*.gz' -o -name '*.1' -o -name '*.old' \\) -mtime +7 -delete"
echo "== NIVEAU 1b : cache VS Code Remote (workspace + VSIX, pas le serveur) =="
for d in /root /home/*; do
  [[ -d "$d/.vscode-server" ]] || continue
  run "find $d/.vscode-server/data/User/workspaceStorage -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
  run "rm -rf $d/.vscode-server/data/CachedExtensionVSIXs"
done

if (( NIVEAU >= 2 )); then
  echo "== NIVEAU 2 : logs runtime + pods morts =="
  # logs containerd / docker individuels trop gros : truncate, ne pas supprimer le fichier
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    run "truncate -s ${CTR_LOG_MAX_MB}M -- '$f'"
  done < <(find /var/lib/docker /var/lib/containerd /var/log/pods /var/lib/kubelet -type f -name '*.log' -size +${CTR_LOG_MAX_MB}M 2>/dev/null || true)

  if command -v kubectl >/dev/null 2>&1; then
    export KUBECONFIG
    if [[ -r "${KUBECONFIG}" ]]; then
      run "kubectl delete pods -A --field-selector=status.phase=Failed --ignore-not-found=true"
      run "kubectl get pods -A --no-headers 2>/dev/null | awk '\$4==\"Evicted\" {print \$1,\$2}' | while read ns name; do kubectl delete pod -n \"\$ns\" \"\$name\" --ignore-not-found=true; done"
    fi
  fi
  if command -v logrotate >/dev/null 2>&1; then
    run "logrotate -f /etc/logrotate.conf"
  fi
fi

if (( NIVEAU >= 3 )); then
  echo "== NIVEAU 3 : prune images non utilisées (fenêtre de maintenance) =="
  if command -v crictl >/dev/null 2>&1; then
    run "crictl --runtime-endpoint ${CONTAINER_RUNTIME_ENDPOINT:-unix:///run/containerd/containerd.sock} rmi --prune"
  fi
  if command -v ctr >/dev/null 2>&1; then
    run "ctr -n k8s.io snapshots prune"
    run "ctr -n k8s.io content prune references || true"
  fi
  if command -v docker >/dev/null 2>&1; then
    run "docker image prune -f"
    run "docker container prune -f"
  fi
  echo "NIVEAU 3 ne touche PAS à Longhorn, etcd, PVC, /var/lib/containerd en rm."
fi

df -hP / | awk 'NR==2 {print "APRES / used="$3" avail="$4" pct="$5}'
echo "LOG=${LOG} FIN_CLEANUP"
