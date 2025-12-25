#!/bin/bash
# script: copy_csv_to_pod.sh (version améliorée)
# Description: Copie tous les fichiers CSV d'un répertoire vers un pod Kubernetes
#              avec suggestions d'importation PostgreSQL intelligentes

# ===========================================
# CONFIGURATION
# ===========================================
POD_NAME="postgresql-clean-0"
NAMESPACE="nova-syndicate"
DEST_DIR="/tmp"
EXTENSION="csv"
DB_NAME="nova_syndicate"
DB_USER="postgres"
#DB_PASSWORD="postgres-password-123"  # Utilisé via PGPASSWORD dans les commandes

# ===========================================
# FONCTIONS UTILITAIRES AMÉLIORÉES
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

function print_command() {
    echo -e "\e[36m$\e[0m $1"
}

# Nouvelle fonction: Génère un nom de table à partir d'un nom de fichier
function generate_table_name() {
    local filename="$1"
    local basename=$(basename "$filename" .csv)
    # Convertir en minuscules, remplacer les caractères spéciaux par _
    echo "$basename" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g'
}

# Nouvelle fonction: Propose des commandes d'importation
function generate_import_commands() {
    local files=("$@")
    
    echo ""
    echo "💡 PROCHAINES ÉTAPES:"
    echo ""
    
    # Option 1: Importation individuelle
    echo "1. IMPORTER DANS POSTGRESQL:"
    echo "────────────────────────────────────────────────────────────────────"
    
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        tablename=$(generate_table_name "$filename")
        
        echo "# Import de $filename"
        print_command "kubectl exec $POD_NAME -n $NAMESPACE -- \\"
        print_command "  psql -U $DB_USER -d $DB_NAME -c \\\"\\\\COPY $tablename FROM '$DEST_DIR/$filename' WITH (FORMAT csv, HEADER true);\\\""
        echo ""
    done
    
    # Option 2: Script d'importation automatique
    echo "────────────────────────────────────────────────────────────────────"
    echo "2. CRÉER UN SCRIPT D'IMPORTATION AUTOMATIQUE:"
    print_command "cat > import_all_tables.sql << 'EOF'"
    
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        tablename=$(generate_table_name "$filename")
        echo "-- Import de $filename"
        echo "DROP TABLE IF EXISTS $tablename CASCADE;"
        echo "CREATE TABLE $tablename AS SELECT * FROM read_csv('$DEST_DIR/$filename', auto_detect=true);"
        echo ""
    done
    
    print_command "EOF"
    echo ""
    print_command "kubectl cp import_all_tables.sql $NAMESPACE/$POD_NAME:$DEST_DIR/import_all_tables.sql"
    print_command "kubectl exec $POD_NAME -n $NAMESPACE -- \\"
    print_command "  psql -U $DB_USER -d $DB_NAME -f $DEST_DIR/import_all_tables.sql"
    
    # Option 3: Vérification
    echo "────────────────────────────────────────────────────────────────────"
    echo "3. VÉRIFICATION:"
    print_command "# Lister les fichiers dans le pod"
    print_command "kubectl exec $POD_NAME -n $NAMESPACE -- ls -lh $DEST_DIR/*.$EXTENSION"
    echo ""
    print_command "# Vérifier les tables dans la base"
    print_command "kubectl exec $POD_NAME -n $NAMESPACE -- \\"
    print_command "  psql -U $DB_USER -d $DB_NAME -c '\\\\dt'"
    
    # Option 4: Nettoyage
    echo "────────────────────────────────────────────────────────────────────"
    echo "4. NETTOYAGE (après import):"
    print_command "# Supprimer les fichiers CSV du pod"
    print_command "kubectl exec $POD_NAME -n $NAMESPACE -- rm -f $DEST_DIR/*.$EXTENSION"
    print_command ""
    print_command "# Supprimer les fichiers CSV locaux (optionnel)"
    print_command "rm -f ${SOURCE_DIR}/*.$EXTENSION"
}

# ===========================================
# VÉRIFICATIONS INITIALES (inchangé)
# ===========================================
print_header

# Déterminer le répertoire source
if [ $# -eq 0 ]; then
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

# Vérifier la connexion au cluster
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
echo "📋 LISTE DES FICHIERS À COPIER:"
echo "┌────────────────────────────────────────────────────┐"

counter=1
total_size=0
table_names=()

for file in "${valid_files[@]}"; do
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    human_size=$(numfmt --to=iec --suffix=B $size 2>/dev/null || echo "${size}B")
    total_size=$((total_size + size))
    
    filename=$(basename "$file")
    tablename=$(generate_table_name "$filename")
    table_names+=("$tablename")
    
    printf "│ %2d. %-25s → %-15s │\n" $counter "$filename" "$tablename"
    ((counter++))
done

human_total=$(numfmt --to=iec --suffix=B $total_size 2>/dev/null || echo "${total_size}B")
echo "├────────────────────────────────────────────────────┤"
printf "│ TOTAL: %-35s %5s │\n" "$file_count fichiers" "$human_total"
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
success_files=()

for file in "${valid_files[@]}"; do
    filename=$(basename "$file")
    
    echo -n "  📤 $filename → /tmp/$filename ... "
    
    if kubectl cp "$file" "$NAMESPACE/$POD_NAME:$DEST_DIR/$filename" &> /tmp/kubectl_cp.log; then
        print_success "OK"
        ((success_count++))
        success_files+=("$filename")
    else
        print_error "ÉCHEC"
        ((fail_count++))
        failed_files+=("$filename")
        
        if [ -f /tmp/kubectl_cp.log ]; then
            echo "      Détail: $(cat /tmp/kubectl_cp.log | head -1)"
        fi
    fi
    
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
    echo "🔍 VÉRIFICATION DANS LE POD:"
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "
        echo 'Fichiers dans $DEST_DIR:'
        ls -lh $DEST_DIR/*.$EXTENSION 2>/dev/null | awk '{printf \"  %-25s (%s)\\n\", \$9, \$5}'
        count=\$(ls $DEST_DIR/*.$EXTENSION 2>/dev/null | wc -l)
        echo \"Total: \$count fichiers\"
    "
    
    # Générer les suggestions d'importation
    generate_import_commands "${success_files[@]}"
fi

if [ $fail_count -gt 0 ]; then
    echo ""
    print_warning "⚠ $fail_count fichiers n'ont pas pu être copiés:"
    for failed in "${failed_files[@]}"; do
        echo "  - $failed"
    done
fi

# ===========================================
# MENU INTERACTIF POUR L'IMPORTATION
# ===========================================
if [ $success_count -gt 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎯 OPTIONS D'IMPORTATION IMMÉDIATE:"
    echo ""
    echo "1. Importer UN fichier spécifique"
    echo "2. Importer TOUS les fichiers"
    echo "3. Générer un script d'importation"
    echo "4. Passer (faire l'import manuellement plus tard)"
    echo ""
    
    read -p "Votre choix (1-4): " import_choice
    
    case $import_choice in
        1)
            echo ""
            echo "📁 FICHIERS DISPONIBLES:"
            for i in "${!success_files[@]}"; do
                echo "  $((i+1)). ${success_files[$i]} → $(generate_table_name "${success_files[$i]}")"
            done
            
            read -p "Numéro du fichier à importer: " file_num
            if [[ $file_num =~ ^[0-9]+$ ]] && [ $file_num -ge 1 ] && [ $file_num -le ${#success_files[@]} ]; then
                filename="${success_files[$((file_num-1))]}"
                tablename=$(generate_table_name "$filename")
                
                echo ""
                echo "⚡ IMPORTATION DE: $filename"
                print_command "kubectl exec $POD_NAME -n $NAMESPACE -- psql -U $DB_USER -d $DB_NAME -c \"\\\\COPY $tablename FROM '$DEST_DIR/$filename' WITH CSV HEADER;\""
                
                # Exécuter la commande
                kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "PGPASSWORD='postgres-password-123' psql -U $DB_USER -d $DB_NAME -c \"\\\\COPY $tablename FROM '$DEST_DIR/$filename' WITH CSV HEADER;\""
                
                # Vérifier
                echo ""
                echo "✅ VÉRIFICATION:"
                kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "PGPASSWORD='postgres-password-123' psql -U $DB_USER -d $DB_NAME -c 'SELECT COUNT(*) as \"$tablename\" FROM $tablename;'"
            else
                print_error "Numéro invalide"
            fi
            ;;
            
        2)
            echo ""
            echo "⚡ IMPORTATION DE TOUS LES FICHIERS..."
            
            # Créer un script d'importation
            import_script="/tmp/import_all_$(date +%s).sql"
            cat > "$import_script" << EOF
-- Script d'importation automatique
-- Généré le $(date)
EOF
            
            for filename in "${success_files[@]}"; do
                tablename=$(generate_table_name "$filename")
                cat >> "$import_script" << EOF

-- Import de $filename
DROP TABLE IF EXISTS $tablename CASCADE;
CREATE TABLE $tablename AS SELECT * FROM read_csv('$DEST_DIR/$filename', auto_detect=true);
SELECT '✅ $filename → $tablename (' || COUNT(*)::text || ' lignes)' FROM $tablename;
EOF
            done
            
            # Copier et exécuter
            kubectl cp "$import_script" "$NAMESPACE/$POD_NAME:$DEST_DIR/import_all.sql"
            echo "📦 Exécution du script d'importation..."
            kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "PGPASSWORD='postgres-password-123' psql -U $DB_USER -d $DB_NAME -f $DEST_DIR/import_all.sql"
            
            # Nettoyer
            rm -f "$import_script"
            kubectl exec "$POD_NAME" -n "$NAMESPACE" -- rm -f "$DEST_DIR/import_all.sql"
            ;;
            
        3)
            echo ""
            echo "📝 GÉNÉRATION DU SCRIPT D'IMPORTATION..."
            script_name="import_tables_$(date +%Y%m%d_%H%M%S).sh"
            
            cat > "$script_name" << 'EOF'
#!/bin/bash
# Script d'importation PostgreSQL généré automatiquement
# Exécuter avec: bash ./nom_du_script.sh

POD_NAME="postgresql-clean-0"
NAMESPACE="nova-syndicate"
DB_USER="postgres"
DB_NAME="test_db"

echo "🚀 Début de l'importation PostgreSQL..."
EOF
            
            for filename in "${success_files[@]}"; do
                tablename=$(generate_table_name "$filename")
                cat >> "$script_name" << EOF

echo "📥 Import de $filename..."
kubectl exec "\$POD_NAME" -n "\$NAMESPACE" -- bash -c "PGPASSWORD='postgres-password-123' psql -U \$DB_USER -d \$DB_NAME -c \\\"\\\\COPY $tablename FROM '/tmp/$filename' WITH CSV HEADER;\\\""
EOF
            done
            
            cat >> "$script_name" << 'EOF'

echo ""
echo "✅ Vérification des imports..."
kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "PGPASSWORD='postgres-password-123' psql -U $DB_USER -d $DB_NAME -c '\dt'"

echo ""
echo "🎉 Importation terminée !"
EOF
            
            chmod +x "$script_name"
            print_success "Script généré: $script_name"
            print_command "./$script_name"
            ;;
    esac
fi

# Nettoyage
rm -f /tmp/kubectl_cp.log

echo ""
print_success "Script terminé avec succès!"
exit 0
