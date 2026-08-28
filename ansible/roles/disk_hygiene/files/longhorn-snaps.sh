#!/usr/bin/env bash
# longhorn-snaps.sh — liste les snapshots Longhorn. Suppression UNIQUEMENT si DELETE_ALL=1 CONFIRM=yes.
# À lancer depuis le control-plane (admin.conf). Jamais depuis le timer.
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
export KUBECONFIG
NS="${LONGHORN_NS:-longhorn-system}"
DELETE_ALL="${DELETE_ALL:-0}"
CONFIRM="${CONFIRM:-no}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl absent" >&2
  exit 1
fi
if [[ ! -r "$KUBECONFIG" ]]; then
  echo "kubeconfig illisible: $KUBECONFIG" >&2
  exit 1
fi

echo "===== snapshots Longhorn ${NS} ====="
kubectl get snapshots.longhorn.io -n "$NS" -o wide 2>/dev/null || echo "(CR snapshots.longhorn.io absente)"
echo
echo "===== volumes Longhorn ====="
kubectl get volumes.longhorn.io -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.state,SIZE:.spec.size,NODE:.status.currentNodeID 2>/dev/null || true
echo
echo "===== PVC monitoring ====="
kubectl get pvc -A 2>/dev/null | awk 'NR==1 || /monitor|grafana|loki|prometheus|zabbix/'

if [[ "$DELETE_ALL" == "1" && "$CONFIRM" == "yes" ]]; then
  echo "SUPPRESSION de tous les snapshots.longhorn.io dans ${NS}"
  kubectl delete snapshots.longhorn.io --all -n "$NS"
else
  echo "Aucune suppression (DELETE_ALL=${DELETE_ALL} CONFIRM=${CONFIRM})."
  echo "Pour le lab: DELETE_ALL=1 CONFIRM=yes $0"
fi
