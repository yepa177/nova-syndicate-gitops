#!/usr/bin/env bash
# hotspots.sh — cartographie rapide de l'espace mal utilisé (lecture seule).
# Sortie ACTION= pour le playbook Ansible.
set -euo pipefail

HOST="$(hostname -s)"
root_pct="$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')"
avail="$(df -hP / | awk 'NR==2 {print $4}')"

bytes() { du -sb "$1" 2>/dev/null | awk '{print $1}'; }
human() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

ctr_overlay="/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs"
ctr_all="/var/lib/containerd"
lh="/var/lib/longhorn"
echo "HOST=${HOST} ROOT_PCT=${root_pct} AVAIL=${avail}"

if   (( root_pct >= 90 )); then echo "STATUT=CRITIQUE"
elif (( root_pct >= 80 )); then echo "STATUT=ALERTE"
elif (( root_pct >= 70 )); then echo "STATUT=WARNING"
else echo "STATUT=OK"
fi

echo "----- POINTS CHAUDS -----"
for p in "$ctr_all" "$ctr_overlay" "$lh" /var/lib/kubelet /var/lib/snapd /snap /var/log /home; do
  [[ -e "$p" ]] || continue
  echo "SIZE $(human "$p")  $p"
done

echo "----- /home (vscode / git) -----"
du -xh -d2 /home /root 2>/dev/null | sort -hr | head -n 20

echo "----- ACTIONS -----"
# seuils en octets
overlay_b="$(bytes "$ctr_overlay")"
lh_b="$(bytes "$lh")"
home_b="$(bytes /home)"
vscode_b=0
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  vscode_b=$(( vscode_b + $(bytes "$d") ))
done < <(find /root /home -maxdepth 2 -type d -name '.vscode-server' 2>/dev/null)

if [[ -n "${overlay_b:-}" && "$overlay_b" -gt $((4 * 1024 * 1024 * 1024)) ]]; then
  echo "ACTION=PRUNE_CRI reason=overlay>4G size=$(human "$ctr_overlay")"
fi
if [[ -n "${lh_b:-}" && "$lh_b" -gt $((1024 * 1024 * 1024)) ]]; then
  echo "ACTION=REVIEW_LONGHORN reason=longhorn>1G size=$(human "$lh") (pas de delete auto)"
fi
if [[ "$vscode_b" -gt $((400 * 1024 * 1024)) ]]; then
  echo "ACTION=CLEAN_VSCODE reason=vscode-server>400M bytes=${vscode_b}"
fi
if [[ -n "${home_b:-}" && "$home_b" -gt $((2 * 1024 * 1024 * 1024)) ]]; then
  echo "ACTION=REVIEW_HOME reason=/home>2G size=$(human /home)"
fi
if (( root_pct >= 80 )); then
  echo "ACTION=CLEANUP_NIVEAU3 reason=root>=80%"
fi
echo "FIN_HOTSPOTS"
