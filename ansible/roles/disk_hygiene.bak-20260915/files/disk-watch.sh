#!/usr/bin/env bash
# disk-watch.sh — mesure seule. Journal /var/log/disk-hygiene/disk-watch.log + syslog.
# exit 2 si / >= THRESH_PCT (défaut 80).
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/default/disk-hygiene}"
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && . "$ENV_FILE"

LOG="${DISK_WATCH_LOG:-/var/log/disk-hygiene/disk-watch.log}"
THRESH_PCT="${THRESH_PCT:-${THRESH_ALERT:-80}}"
mkdir -p "$(dirname "$LOG")"

if [[ -z "${CONTAINER_RUNTIME_ENDPOINT:-}" ]]; then
  if [[ -S /run/containerd/containerd.sock ]]; then
    export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
  fi
fi

ts="$(date -Is)"
host="$(hostname -s)"
{
  echo "===== ${ts} ${host} ====="
  df -hT | awk 'NR==1 || $7=="/" || /containerd/ || /longhorn/'
  echo "-- inodes / --"
  df -iP / | tail -1
  echo "-- top /var/lib --"
  du -xh --max-depth=1 /var/lib 2>/dev/null | sort -h | tail -8
  echo "-- containerd overlay --"
  du -sh /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs 2>/dev/null || true
  echo "-- longhorn --"
  du -sh /var/lib/longhorn 2>/dev/null || true
  echo "-- vscode-server --"
  du -sh /root/.vscode-server /home/*/.vscode-server 2>/dev/null || true
  echo "-- crictl images --"
  crictl images 2>/dev/null | wc -l || true
} | tee -a "$LOG"

used="$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')"
if [[ "${used}" -ge "${THRESH_PCT}" ]]; then
  logger -t disk-watch -p local0.warning "${host} root ${used}% (>=${THRESH_PCT}%)"
  echo "${ts} WARN ${host} root=${used}%" >> "$LOG"
  exit 2
fi
logger -t disk-watch -p local0.info "${host} root ${used}% ok"
exit 0
