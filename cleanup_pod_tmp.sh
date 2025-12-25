#!/bin/bash
# script: cleanup_pod_tmp.sh
# Description: Nettoie les fichiers dans le /tmp d'un pod Kubernetes
# Usage: ./cleanup_pod_tmp.sh [pod_name] [namespace]

# ===========================================
# CONFIGURATION
# ===========================================
DEFAULT_POD="postgresql-clean-0"
DEFAULT_NAMESPACE="nova-syndicate"
TMP_DIR="/tmp"

# ===========================================
# FONCTIONS UTILITAIRES
# ===========================================
function print_header() {
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║       NETTOYAGE DES FICHIERS /tmp DU POD            ║"
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

function get_file_type() {
    local file="$1"
    if [[ "$file" == *.csv ]]; then
        echo "CSV"
    elif [[ "$file" == *.sql ]]; then
        echo "SQL"
    elif [[ "$file" == *.log ]] || [[ "$file" == *.txt ]]; then
        echo "LOG"
    elif [[ "$file" == *.bak ]] || [[ "$file" == *.backup ]]; then
        echo "BACKUP"
    elif [[ "$file" == *.tar ]] || [[ "$file" == *.gz ]] || [[ "$file" == *.zip ]]; then
        echo "ARCHIVE"
    else
        echo "AUTRE"
    fi
}

# ===========================================
# VÉRIFICATIONS INITIALES
# ===========================================
print_header

# Déterminer le pod et namespace
if [ $# -ge 1 ]; then
    POD_NAME="$1"
else
    POD_NAME="$DEFAULT_POD"
fi

if [ $# -ge 2 ]; then
    NAMESPACE="$2"
else
    NAMESPACE="$DEFAULT_NAMESPACE"
fi

print_info "Pod: $POD_NAME"
print_info "Namespace: $NAMESPACE"
print_info "Répertoire: $TMP_DIR"
echo ""

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
    echo ""
    echo "Pods disponibles dans $NAMESPACE:"
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi

# ===========================================
# SCAN DES FICHIERS DANS /tmp
# ===========================================
echo "🔍 SCAN DES FICHIERS DANS $TMP_DIR..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Récupérer la liste des fichiers avec détails
echo "Récupération des informations des fichiers..."
mapfile -t file_list < <(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "
    # Lister les fichiers avec détails
    find $TMP_DIR -maxdepth 1 -type f ! -name '.*' 2>/dev/null | while read file; do
        if [ -f \"\$file\" ]; then
            size=\$(stat -c%s \"\$file\" 2>/dev/null || stat -f%z \"\$file\" 2>/dev/null)
            mtime=\$(stat -c%y \"\$file\" 2>/dev/null || stat -f%Sm \"\$file\" 2>/dev/null | cut -d' ' -f1-3)
            filename=\$(basename \"\$file\")
            echo \"\$filename|\$size|\$mtime\"
        fi
    done
" 2>/dev/null)

if [ ${#file_list[@]} -eq 0 ]; then
    print_info "Aucun fichier trouvé dans $TMP_DIR du pod $POD_NAME"
    echo ""
    echo "Vérification rapide:"
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- ls -la "$TMP_DIR" 2>/dev/null || echo "  (répertoire vide ou inaccessible)"
    exit 0
fi

print_success "Nombre de fichiers trouvés: ${#file_list[@]}"
echo ""

# ===========================================
# AFFICHAGE DE LA LISTE DES FICHIERS
# ===========================================
echo "📋 LISTE DES FICHIERS DISPONIBLES:"
echo "┌────┬──────────────────────────────┬────────────┬─────────────────────┐"
echo "│ #  │ Nom du fichier               │ Taille     │ Dernière modif.     │"
echo "├────┼──────────────────────────────┼────────────┼─────────────────────┤"

file_names=()
counter=1
total_size=0

for file_info in "${file_list[@]}"; do
    IFS='|' read -r filename size mtime <<< "$file_info"
    file_names+=("$filename")
    
    # Convertir la taille en format humain
    if [ $size -ge 1073741824 ]; then
        human_size=$(echo "scale=2; $size/1073741824" | bc)GB
    elif [ $size -ge 1048576 ]; then
        human_size=$(echo "scale=2; $size/1048576" | bc)MB
    elif [ $size -ge 1024 ]; then
        human_size=$(echo "scale=2; $size/1024" | bc)KB
    else
        human_size="${size}B"
    fi
    
    # Tronquer le nom si trop long
    display_name="$filename"
    if [ ${#display_name} -gt 26 ]; then
        display_name="${display_name:0:23}..."
    fi
    
    # Afficher la ligne
    printf "│ %2d │ %-26s │ %-10s │ %-19s │\n" "$counter" "$display_name" "$human_size" "${mtime:0:19}"
    
    total_size=$((total_size + size))
    ((counter++))
done

# Convertir la taille totale
if [ $total_size -ge 1073741824 ]; then
    human_total=$(echo "scale=2; $total_size/1073741824" | bc)GB
elif [ $total_size -ge 1048576 ]; then
    human_total=$(echo "scale=2; $total_size/1048576" | bc)MB
elif [ $total_size -ge 1024 ]; then
    human_total=$(echo "scale=2; $total_size/1024" | bc)KB
else
    human_total="${total_size}B"
fi

echo "├────┼──────────────────────────────┼────────────┼─────────────────────┤"
printf "│    │ TOTAL: %-20d │ %-10s │                     │\n" "${#file_list[@]}" "$human_total"
echo "└────┴──────────────────────────────┴────────────┴─────────────────────┘"
echo ""

# ===========================================
# MENU DE SÉLECTION
# ===========================================
echo "🎯 OPTIONS DE SUPPRESSION:"
echo ""
echo "1. Supprimer un fichier spécifique"
echo "2. Supprimer plusieurs fichiers"
echo "3. Supprimer par type (CSV, SQL, etc.)"
echo "4. Supprimer TOUS les fichiers"
echo "5. Afficher le contenu d'un fichier"
echo "6. Quitter"
echo ""

while true; do
    read -p "Votre choix (1-6): " choice
    
    case $choice in
        1)
            # Supprimer un fichier spécifique
            echo ""
            echo "🗑️  SUPPRESSION D'UN FICHIER SPÉCIFIQUE"
            echo "──────────────────────────────────────"
            
            read -p "Numéro du fichier à supprimer: " file_num
            if [[ $file_num =~ ^[0-9]+$ ]] && [ $file_num -ge 1 ] && [ $file_num -le ${#file_names[@]} ]; then
                filename="${file_names[$((file_num-1))]}"
                filetype=$(get_file_type "$filename")
                
                echo ""
                print_warning "⚠ Vous allez supprimer:"
                echo "   Fichier: $filename"
                echo "   Type: $filetype"
                echo "   Emplacement: $TMP_DIR/$filename"
                echo ""
                
                read -p "Confirmer la suppression? (o/N): " -n 1 -r
                echo ""
                
                if [[ $REPLY =~ ^[OoYy]$ ]]; then
                    echo "Suppression en cours..."
                    if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- rm -f "$TMP_DIR/$filename"; then
                        print_success "✅ Fichier supprimé: $filename"
                    else
                        print_error "❌ Échec de la suppression"
                    fi
                else
                    print_info "Suppression annulée"
                fi
            else
                print_error "Numéro invalide"
            fi
            ;;
            
        2)
            # Supprimer plusieurs fichiers
            echo ""
            echo "🗑️  SUPPRESSION DE PLUSIEURS FICHIERS"
            echo "──────────────────────────────────────"
            echo "Entrez les numéros séparés par des espaces (ex: 1 3 5)"
            echo "Ou une plage (ex: 2-4)"
            echo ""
            
            read -p "Numéros des fichiers à supprimer: " selection
            
            # Traiter la sélection
            files_to_delete=()
            
            # Séparer par espace
            IFS=' ' read -ra items <<< "$selection"
            
            for item in "${items[@]}"; do
                if [[ $item =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    # C'est une plage
                    start=${BASH_REMATCH[1]}
                    end=${BASH_REMATCH[2]}
                    if [ $start -le $end ] && [ $start -ge 1 ] && [ $end -le ${#file_names[@]} ]; then
                        for ((i=start; i<=end; i++)); do
                            files_to_delete+=("${file_names[$((i-1))]}")
                        done
                    fi
                elif [[ $item =~ ^[0-9]+$ ]] && [ $item -ge 1 ] && [ $item -le ${#file_names[@]} ]; then
                    # C'est un numéro simple
                    files_to_delete+=("${file_names[$((item-1))]}")
                fi
            done
            
            if [ ${#files_to_delete[@]} -eq 0 ]; then
                print_error "Aucun fichier valide sélectionné"
                continue
            fi
            
            echo ""
            print_warning "⚠ Vous allez supprimer ${#files_to_delete[@]} fichiers:"
            for file in "${files_to_delete[@]}"; do
                echo "   - $file"
            done
            echo ""
            
            read -p "Confirmer la suppression? (o/N): " -n 1 -r
            echo ""
            
            if [[ $REPLY =~ ^[OoYy]$ ]]; then
                echo "Suppression en cours..."
                deleted=0
                failed=0
                
                for file in "${files_to_delete[@]}"; do
                    if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- rm -f "$TMP_DIR/$file"; then
                        echo "  ✅ $file"
                        ((deleted++))
                    else
                        echo "  ❌ $file"
                        ((failed++))
                    fi
                done
                
                echo ""
                if [ $deleted -gt 0 ]; then
                    print_success "$deleted fichiers supprimés avec succès"
                fi
                if [ $failed -gt 0 ]; then
                    print_error "$failed fichiers n'ont pas pu être supprimés"
                fi
            else
                print_info "Suppression annulée"
            fi
            ;;
            
        3)
            # Supprimer par type
            echo ""
            echo "🗑️  SUPPRESSION PAR TYPE DE FICHIER"
            echo "──────────────────────────────────────"
            echo "1. Tous les fichiers CSV"
            echo "2. Tous les fichiers SQL"
            echo "3. Tous les fichiers LOG/TXT"
            echo "4. Tous les fichiers de backup"
            echo "5. Tous les fichiers archives"
            echo "6. Retour"
            echo ""
            
            read -p "Choix du type (1-6): " type_choice
            
            case $type_choice in
                1) pattern="*.csv"; type_name="CSV" ;;
                2) pattern="*.sql"; type_name="SQL" ;;
                3) pattern="*.log *.txt"; type_name="LOG/TXT" ;;
                4) pattern="*.bak *.backup"; type_name="BACKUP" ;;
                5) pattern="*.tar *.gz *.zip"; type_name="ARCHIVE" ;;
                6) continue ;;
                *) print_error "Choix invalide"; continue ;;
            esac
            
            # Trouver les fichiers correspondants
            matching_files=()
            for filename in "${file_names[@]}"; do
                for pat in $pattern; do
                    if [[ $filename == $pat ]]; then
                        matching_files+=("$filename")
                        break
                    fi
                done
            done
            
            if [ ${#matching_files[@]} -eq 0 ]; then
                print_info "Aucun fichier $type_name trouvé"
                continue
            fi
            
            echo ""
            print_warning "⚠ Vous allez supprimer ${#matching_files[@]} fichiers $type_name:"
            for file in "${matching_files[@]}"; do
                echo "   - $file"
            done
            echo ""
            
            read -p "Confirmer la suppression? (o/N): " -n 1 -r
            echo ""
            
            if [[ $REPLY =~ ^[OoYy]$ ]]; then
                echo "Suppression en cours..."
                for file in "${matching_files[@]}"; do
                    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- rm -f "$TMP_DIR/$file" && \
                    echo "  ✅ $file" || echo "  ❌ $file"
                done
                print_success "Suppression des fichiers $type_name terminée"
            else
                print_info "Suppression annulée"
            fi
            ;;
            
        4)
            # Supprimer tous les fichiers
            echo ""
            echo "☢️  SUPPRESSION DE TOUS LES FICHIERS"
            echo "──────────────────────────────────────"
            print_warning "⚠ ATTENTION: Cette action est irréversible!"
            print_warning "  Vous allez supprimer ${#file_names[@]} fichiers"
            echo ""
            
            read -p "Êtes-vous ABSOLUMENT certain? (tapez 'DELETE' pour confirmer): " confirmation
            
            if [ "$confirmation" = "DELETE" ]; then
                echo ""
                echo "Suppression en cours..."
                
                # Supprimer tous les fichiers
                if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "
                    count=0
                    for file in $TMP_DIR/*; do
                        if [ -f \"\$file\" ] && [[ \"\$(basename \$file)\" != .* ]]; then
                            rm -f \"\$file\"
                            ((count++))
                        fi
                    done
                    echo \"\$count fichiers supprimés\"
                "; then
                    print_success "✅ Tous les fichiers ont été supprimés"
                else
                    print_error "❌ Échec lors de la suppression"
                fi
            else
                print_info "Suppression annulée"
            fi
            ;;
            
        5)
            # Afficher le contenu d'un fichier
            echo ""
            echo "📄 AFFICHAGE DU CONTENU D'UN FICHIER"
            echo "──────────────────────────────────────"
            
            read -p "Numéro du fichier à afficher: " file_num
            if [[ $file_num =~ ^[0-9]+$ ]] && [ $file_num -ge 1 ] && [ $file_num -le ${#file_names[@]} ]; then
                filename="${file_names[$((file_num-1))]}"
                filetype=$(get_file_type "$filename")
                
                echo ""
                echo "Fichier: $filename"
                echo "Type: $filetype"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                
                # Afficher les premières lignes
                if [[ "$filetype" == "CSV" ]] || [[ "$filetype" == "LOG" ]] || [[ "$filetype" == "SQL" ]]; then
                    echo "Premières 10 lignes:"
                    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- head -n 10 "$TMP_DIR/$filename" 2>/dev/null
                    
                    echo ""
                    read -p "Afficher plus de lignes? (o/N): " -n 1 -r
                    echo ""
                    if [[ $REPLY =~ ^[OoYy]$ ]]; then
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        kubectl exec "$POD_NAME" -n "$NAMESPACE" -- cat "$TMP_DIR/$filename" 2>/dev/null | head -n 50
                    fi
                else
                    # Pour les fichiers binaires, afficher seulement les infos
                    echo "Contenu (fichier binaire ou texte long):"
                    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- file "$TMP_DIR/$filename" 2>/dev/null
                fi
                
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "Taille: $(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- wc -c "$TMP_DIR/$filename" 2>/dev/null | awk '{print $1}') octets"
            else
                print_error "Numéro invalide"
            fi
            ;;
            
        6)
            echo ""
            print_info "Au revoir!"
            exit 0
            ;;
            
        *)
            print_error "Choix invalide"
            ;;
    esac
    
    echo ""
    read -p "Voulez-vous effectuer une autre opération? (o/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        break
    fi
    
    # Re-scanner les fichiers
    echo ""
    echo "🔄 Re-scan des fichiers..."
    mapfile -t file_list < <(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "
        find $TMP_DIR -maxdepth 1 -type f ! -name '.*' 2>/dev/null | while read file; do
            if [ -f \"\$file\" ]; then
                size=\$(stat -c%s \"\$file\" 2>/dev/null || stat -f%z \"\$file\" 2>/dev/null)
                mtime=\$(stat -c%y \"\$file\" 2>/dev/null || stat -f%Sm \"\$file\" 2>/dev/null | cut -d' ' -f1-3)
                filename=\$(basename \"\$file\")
                echo \"\$filename|\$size|\$mtime\"
            fi
        done
    " 2>/dev/null)
    
    if [ ${#file_list[@]} -eq 0 ]; then
        print_info "Aucun fichier restant dans $TMP_DIR"
        exit 0
    fi
    
    # Mettre à jour la liste
    file_names=()
    for file_info in "${file_list[@]}"; do
        IFS='|' read -r filename size mtime <<< "$file_info"
        file_names+=("$filename")
    done
    
    echo "📋 Fichiers restants: ${#file_names[@]}"
    echo ""
done

# ===========================================
# VÉRIFICATION FINALE
# ===========================================
echo ""
echo "🔍 VÉRIFICATION FINALE:"
kubectl exec "$POD_NAME" -n "$NAMESPACE" -- ls -la "$TMP_DIR" 2>/dev/null || print_info "Répertoire $TMP_DIR vide"

echo ""
print_success "Script terminé avec succès!"
exit 0
