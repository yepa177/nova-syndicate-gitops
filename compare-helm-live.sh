#!/bin/bash

echo "=== COMPARAISON HELM CHART vs RESSOURCES LIVE ==="
echo ""

echo "1. ANNOTATIONS dans le chart Helm:"
if grep -q "argocd.argoproj.io/instance" helm-manifest.yaml; then
    echo "    Présentes"
    grep -c "argocd.argoproj.io/instance" helm-manifest.yaml
else
    echo "    ABSENTES"
fi
echo ""

echo "2. ANNOTATIONS dans les ressources live:"
kubectl get configmap,secret,deployment,service -n argocd -o yaml | grep -c "argocd.argoproj.io/instance"
echo ""

echo "3. LABELS dans le chart Helm:"
grep -c "app.kubernetes.io/instance" helm-manifest.yaml
echo ""

echo "4. LABELS dans les ressources live:"
kubectl get configmap,secret,deployment,service -n argocd -o yaml | grep -c "app.kubernetes.io/instance"
echo ""

echo "5. Différence visible:"
echo "   - Chart Helm: app.kubernetes.io/instance: argocd (LABEL)"
echo "   - Ressources live: argocd.argoproj.io/instance: argocd (ANNOTATION ajoutée par ArgoCD)"
