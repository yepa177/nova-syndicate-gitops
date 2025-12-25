#!/bin/bash
# script: copy_csv_to_pod.sh
# Description: Copie tous les fichiers CSV d'un répertoire vers un pod Kubernetes
# Usage: ./copy_csv_to_pod.sh [répertoire_source]

# ===========================================
# CONFIGURATION
# ===========================================
POD_NAME="postgresql-clean-0"
NAMESPACE="nova-syndicate"
DEST_DIR="/tmp"
EXTENSION="csv"

# ===========================================
# FONCTIONS UTILITAIRES
# ===========================================
function print_header() {
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║       COPIE DE FICHIERS CSV VERS POD KUBERNETES      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
}

function print_success() {
    echo -e "\e[32m✓ $1\e[0m"
}

function print_error() {
    echo -e "\e[31m✗ ERREUR: $1\e[0m"
}

function print_info() {
    echo -e "\e[34mℹ $1\e[0m"
}

function print_warning() {
    echo -e "\e[33m⚠ $1\e[0m"
}

# ===========================================
# VÉRIFICATIONS INITIALES
# ===========================================
print_header

# Déterminer le répertoire source
if [ $# -eq 0 ]; then
    # Si aucun argument, utiliser le répertoire par défaut
    SOURCE_DIR="$HOME/nova-syndicate-gitops/nova-syndicate-csv"
    print_info "Aucun répertoire spécifié, utilisation du répertoire par défaut:"
    print_info "  $SOURCE_DIR"
else
    SOURCE_DIR="$1"
fi

# Vérifier si kubectl est installé
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

# Vérifier la connexion au cluster Kubernetes
if ! kubectl cluster-info &> /dev/null; then
    print_error "Impossible de se connecter au cluster Kubernetes"
    exit 1
fi

# Vérifier si le pod existe
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &> /dev/null; then
    print_error "Le pod '$POD_NAME' n'existe pas dans le namespace '$NAMESPACE'"
    echo "Pods disponibles dans $NAMESPACE:"
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi

# Vérifier si le répertoire source existe
if [ ! -d "$SOURCE_DIR" ]; then
    print_error "Le répertoire source n'existe pas:"
    print_error "  $SOURCE_DIR"
    echo ""
    echo "Créer le répertoire avec:"
    echo "  mkdir -p \"$SOURCE_DIR\""
    exit 1
fi

# ===========================================
# LISTE DES FICHIERS CSV
# ===========================================
echo "📁 RÉPERTOIRE SOURCE: $SOURCE_DIR"
echo "🔍 Recherche des fichiers .$EXTENSION..."

# Compter les fichiers CSV
csv_files=("$SOURCE_DIR"/*."$EXTENSION")
file_count=0
valid_files=()

for file in "${csv_files[@]}"; do
    if [ -f "$file" ]; then
        ((file_count++))
        valid_files+=("$file")
    fi
done

if [ $file_count -eq 0 ]; then
    print_warning "Aucun fichier .$EXTENSION trouvé dans le répertoire"
    echo ""
    echo "Fichiers présents dans $SOURCE_DIR:"
    ls -la "$SOURCE_DIR/" 2>/dev/null || echo "  (répertoire vide)"
    exit 0
fi

print_success "Nombre de fichiers .$EXTENSION trouvés: $file_count"
echo ""

# ===========================================
# AFFICHAGE DE LA LISTE DES FICHIERS
# ===========================================
echo "�� LISTE DES FICHIERS À COPIER:"
echo "┌────────────────────────────────────────────────────┐"
counter=1
total_size=0
for file in "${valid_files[@]}"; do
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    human_size=$(numfmt --to=iec --suffix=B $size 2>/dev/null || echo "${size}B")
    total_size=$((total_size + size))
    printf "│ %2d. %-30s %10s │\n" $counter "$(basename "$file")" "$human_size"
    ((counter++))
done

human_total=$(numfmt --to=iec --suffix=B $total_size 2>/dev/null || echo "${total_size}B")
echo "├────────────────────────────────────────────────────┤"
printf "│ TOTAL: %-25s %10s │\n" "$file_count fichiers" "$human_total"
echo "└────────────────────────────────────────────────────┘"
echo ""

# ===========================================
# CONFIRMATION
# ===========================================
read -p "Voulez-vous copier ces fichiers vers le pod? (o/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
    print_info "Opération annulée par l'utilisateur"
    exit 0
fi

# ===========================================
# COPIE DES FICHIERS
# ===========================================
echo ""
echo "🚀 DÉBUT DE LA COPIE..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

success_count=0
fail_count=0
failed_files=()

for file in "${valid_files[@]}"; do
    filename=$(basename "$file")
    
    echo -n "  📤 $filename ... "
    
    # Copier le fichier
    if kubectl cp "$file" "$NAMESPACE/$POD_NAME:$DEST_DIR/$filename" &> /tmp/kubectl_cp.log; then
        print_success "OK"
        ((success_count++))
    else
        print_error "ÉCHEC"
        ((fail_count++))
        failed_files+=("$filename")
        
        # Afficher l'erreur détaillée
        if [ -f /tmp/kubectl_cp.log ]; then
            echo "      Détail: $(cat /tmp/kubectl_cp.log | head -1)"
        fi
    fi
    
    # Petite pause pour éviter de surcharger
    sleep 0.1
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ===========================================
# RAPPORT FINAL
# ===========================================
echo ""
echo "📊 RAPPORT FINAL:"
echo "┌─────────────────────────────────────────────┐"
printf "│ %-20s %20s │\n" "Fichiers trouvés:" "$file_count"
printf "│ %-20s %20s │\n" "Copie réussie:" "$success_count"
printf "│ %-20s %20s │\n" "Copie échouée:" "$fail_count"
echo "└─────────────────────────────────────────────┘"

if [ $success_count -gt 0 ]; then
    print_success "✅ $success_count fichiers copiés avec succès vers:"
    print_success "   Pod: $POD_NAME"
    print_success "   Destination: $DEST_DIR/"
    
    # Vérification dans le pod
    echo ""
    echo "🔍 Vérification dans le pod..."
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "
        echo 'Fichiers CSV dans $DEST_DIR:'
        ls -lh $DEST_DIR/*.$EXTENSION 2>/dev/null | awk '{print \"  \" \$9 \" (\" \$5 \")\"}'
        count=\$(ls $DEST_DIR/*.$EXTENSION 2>/dev/null | wc -l)
        echo \"Total: \$count fichiers\"
    "
fi

if [ $fail_count -gt 0 ]; then
    echo ""
    print_warning "⚠ $fail_count fichiers n'ont pas pu être copiés:"
    for failed in "${failed_files[@]}"; do
        echo "  - $failed"
    done
fi

# ===========================================
# SUGGESTIONS POUR LA SUITE
# ===========================================
if [ $success_count -gt 0 ]; then
    echo ""
    echo "💡 PROCHAINES ÉTAPES:"
    echo "   1. Importer dans PostgreSQL:"
    echo "      kubectl exec $POD_NAME -n $NAMESPACE -- \\"
    echo "        psql -U postgres -d test_db -c \"\COPY table_name FROM '/tmp/fichier.csv' CSV HEADER;\""
    echo ""
    echo "   2. Lister tous les fichiers copiés:"
    echo "      kubectl exec $POD_NAME -n $NAMESPACE -- ls -la /tmp/*.csv"
fi

# Nettoyage
rm -f /tmp/kubectl_cp.log

echo ""
print_success "Script terminé avec succès!"
exit 0
