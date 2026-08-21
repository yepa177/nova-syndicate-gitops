#!/bin/bash
# cleanup-pods.sh - Nettoyer les pods en erreur

echo "🔍 Recherche des pods problématiques..."
PODS=$(kubectl get pods -A | grep -E 'ContainerStatusUnknown|Evicted|Init:0/1|Error|Completed')

if [ -z "$PODS" ]; then
  echo "✅ Aucun pod problématique trouvé"
  exit 0
fi

echo "📋 Pods à supprimer :"
echo "$PODS"
echo

read -p "Confirmer la suppression ? (o/N): " confirm
if [[ $confirm == [oO] ]]; then
  echo "$PODS" | awk '{print $1, $2}' | while read ns pod; do
    echo "🗑️  Suppression de $pod dans $ns..."
    kubectl delete pod -n $ns $pod
  done
  echo "✅ Nettoyage terminé"
else
  echo "❌ Annulation"
fi
